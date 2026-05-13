using System.Collections.Concurrent;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;

namespace HermesAgent.Gui;

public sealed record GatewayEvent(string Type, JsonElement Payload);

public sealed class GatewayClient : IAsyncDisposable
{
    private readonly HermesClient _client;
    private readonly ConcurrentDictionary<string, TaskCompletionSource<JsonElement>> _pending = new();
    private ClientWebSocket? _socket;
    private int _requestId;

    public event Action<GatewayEvent>? EventReceived;
    public string? SessionId { get; private set; }

    public GatewayClient(HermesClient client)
    {
        _client = client;
    }

    public async Task ConnectAsync(CancellationToken cancellationToken)
    {
        if (_socket?.State == WebSocketState.Open)
        {
            return;
        }

        var token = await _client.GetNativeSessionTokenAsync(cancellationToken);
        if (string.IsNullOrWhiteSpace(token))
        {
            throw new InvalidOperationException("后端没有返回会话 token。");
        }

        var ws = new ClientWebSocket();
        var uri = new Uri($"ws://127.0.0.1:{_client.Port}/api/ws?token={Uri.EscapeDataString(token)}");
        await ws.ConnectAsync(uri, cancellationToken);
        _socket = ws;
        _ = Task.Run(() => ReceiveLoopAsync(ws));

        var created = await RequestAsync("session.create", new { cols = 100 }, cancellationToken);
        if (created.TryGetProperty("session_id", out var sid))
        {
            SessionId = sid.GetString();
        }
    }

    public async Task SubmitAsync(string text, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(SessionId))
        {
            throw new InvalidOperationException("聊天会话还没有创建。");
        }
        await RequestAsync("prompt.submit", new { session_id = SessionId, text }, cancellationToken);
    }

    private async Task<JsonElement> RequestAsync(string method, object parameters, CancellationToken cancellationToken)
    {
        var socket = _socket;
        if (socket is null || socket.State != WebSocketState.Open)
        {
            throw new InvalidOperationException("聊天连接未打开。");
        }

        var id = $"gui-{Interlocked.Increment(ref _requestId)}";
        var tcs = new TaskCompletionSource<JsonElement>(TaskCreationOptions.RunContinuationsAsynchronously);
        _pending[id] = tcs;
        var body = JsonSerializer.Serialize(new
        {
            jsonrpc = "2.0",
            id,
            method,
            @params = parameters
        });
        var bytes = Encoding.UTF8.GetBytes(body);
        await socket.SendAsync(bytes, WebSocketMessageType.Text, true, cancellationToken);
        using var registration = cancellationToken.Register(() => tcs.TrySetCanceled(cancellationToken));
        return await tcs.Task;
    }

    private async Task ReceiveLoopAsync(ClientWebSocket socket)
    {
        var buffer = new byte[65536];
        var builder = new StringBuilder();
        try
        {
            while (socket.State == WebSocketState.Open)
            {
                var result = await socket.ReceiveAsync(buffer, CancellationToken.None);
                if (result.MessageType == WebSocketMessageType.Close)
                {
                    break;
                }
                builder.Append(Encoding.UTF8.GetString(buffer, 0, result.Count));
                if (!result.EndOfMessage)
                {
                    continue;
                }

                Dispatch(builder.ToString());
                builder.Clear();
            }
        }
        catch (Exception ex)
        {
            EventReceived?.Invoke(new GatewayEvent("error", JsonSerializer.SerializeToElement(new { message = ex.Message })));
        }
    }

    private void Dispatch(string json)
    {
        using var doc = JsonDocument.Parse(json);
        var root = doc.RootElement.Clone();

        if (root.TryGetProperty("id", out var idElement))
        {
            var id = idElement.GetString() ?? "";
            if (_pending.TryRemove(id, out var pending))
            {
                if (root.TryGetProperty("error", out var error))
                {
                    pending.TrySetException(new InvalidOperationException(error.ToString()));
                }
                else if (root.TryGetProperty("result", out var result))
                {
                    pending.TrySetResult(result.Clone());
                }
                else
                {
                    pending.TrySetResult(default);
                }
            }
            return;
        }

        if (!root.TryGetProperty("method", out var method) || method.GetString() != "event")
        {
            return;
        }
        if (!root.TryGetProperty("params", out var parameters))
        {
            return;
        }
        var type = parameters.TryGetProperty("type", out var typeElement) ? typeElement.GetString() ?? "" : "";
        var payload = parameters.TryGetProperty("payload", out var payloadElement)
            ? payloadElement.Clone()
            : JsonSerializer.SerializeToElement(new { });
        EventReceived?.Invoke(new GatewayEvent(type, payload));
    }

    public async ValueTask DisposeAsync()
    {
        if (_socket is { State: WebSocketState.Open } socket)
        {
            await socket.CloseAsync(WebSocketCloseStatus.NormalClosure, "closing", CancellationToken.None);
        }
        _socket?.Dispose();
    }
}
