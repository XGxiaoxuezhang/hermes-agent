using System.Diagnostics;
using System.IO;
using System.Net.Http;
using System.Text.Json;

namespace HermesAgent.Gui;

public sealed record HermesStatus(
    bool DashboardOnline,
    string Version,
    string HermesHome,
    string ConfigPath,
    string EnvPath,
    bool GatewayRunning,
    int? GatewayPid,
    string? GatewayState,
    string? GatewayExitReason,
    int ActiveSessions,
    string? Error
);

public sealed record ActionStatus(
    string Name,
    bool Running,
    int? ExitCode,
    int? Pid,
    IReadOnlyList<string> Lines
);

public sealed class HermesClient
{
    private readonly HttpClient _http = new()
    {
        Timeout = TimeSpan.FromSeconds(3)
    };

    public int Port { get; set; } = 9119;
    public string RepoRoot { get; set; } = RepoLocator.FindRepoRoot();

    public string BaseUrl => $"http://127.0.0.1:{Port}";

    public string LocalStateDir => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "HermesAgent"
    );

    public async Task<HermesStatus> GetStatusAsync(CancellationToken cancellationToken)
    {
        try
        {
            using var response = await _http.GetAsync($"{BaseUrl}/api/status", cancellationToken);
            response.EnsureSuccessStatusCode();
            await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
            using var doc = await JsonDocument.ParseAsync(stream, cancellationToken: cancellationToken);
            var root = doc.RootElement;

            return new HermesStatus(
                DashboardOnline: true,
                Version: GetString(root, "version") ?? "unknown",
                HermesHome: GetString(root, "hermes_home") ?? "",
                ConfigPath: GetString(root, "config_path") ?? "",
                EnvPath: GetString(root, "env_path") ?? "",
                GatewayRunning: GetBool(root, "gateway_running"),
                GatewayPid: GetInt(root, "gateway_pid"),
                GatewayState: GetString(root, "gateway_state"),
                GatewayExitReason: GetString(root, "gateway_exit_reason"),
                ActiveSessions: GetInt(root, "active_sessions") ?? 0,
                Error: null
            );
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException or IOException)
        {
            return new HermesStatus(
                DashboardOnline: false,
                Version: "offline",
                HermesHome: "",
                ConfigPath: "",
                EnvPath: "",
                GatewayRunning: false,
                GatewayPid: null,
                GatewayState: null,
                GatewayExitReason: null,
                ActiveSessions: 0,
                Error: ex.Message
            );
        }
    }

    public Task StartDashboardAsync(bool noTui = false)
    {
        var script = ScriptPath("start-dashboard-background.ps1");
        var args = $"-NoProfile -ExecutionPolicy Bypass -File \"{script}\" -Port {Port}";
        if (noTui)
        {
            args += " -NoTui";
        }
        StartPowerShell(args, hidden: true);
        return Task.CompletedTask;
    }

    public Task StopDashboardAsync()
    {
        var script = ScriptPath("stop-dashboard-background.ps1");
        StartPowerShell($"-NoProfile -ExecutionPolicy Bypass -File \"{script}\" -Port {Port}", hidden: true);
        return Task.CompletedTask;
    }

    public async Task<ActionStatus> RestartGatewayAsync(CancellationToken cancellationToken)
    {
        await PostAsync("/api/gateway/restart", cancellationToken);
        return await GetActionStatusAsync("gateway-restart", cancellationToken);
    }

    public Task UpdateVisibleAsync()
    {
        var script = ScriptPath("update-dashboard-visible.ps1");
        var logFile = Path.Combine(LocalStateDir, "hermes-update.log");
        var args =
            $"-NoProfile -ExecutionPolicy Bypass -File \"{script}\" -InstallDir \"{RepoRoot}\" -Port {Port} -LogFile \"{logFile}\"";
        StartPowerShell(args, hidden: false);
        return Task.CompletedTask;
    }

    public async Task<ActionStatus> GetActionStatusAsync(string name, CancellationToken cancellationToken)
    {
        using var response = await _http.GetAsync($"{BaseUrl}/api/actions/{Uri.EscapeDataString(name)}/status?lines=500", cancellationToken);
        response.EnsureSuccessStatusCode();
        await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
        using var doc = await JsonDocument.ParseAsync(stream, cancellationToken: cancellationToken);
        var root = doc.RootElement;
        var lines = new List<string>();
        if (root.TryGetProperty("lines", out var array) && array.ValueKind == JsonValueKind.Array)
        {
            foreach (var item in array.EnumerateArray())
            {
                lines.Add(item.GetString() ?? "");
            }
        }

        return new ActionStatus(
            GetString(root, "name") ?? name,
            GetBool(root, "running"),
            GetInt(root, "exit_code"),
            GetInt(root, "pid"),
            lines
        );
    }

    public string ReadLocalLog(string name, int maxChars = 24000)
    {
        var candidates = name switch
        {
            "dashboard" => new[] { Path.Combine(LocalStateDir, "dashboard.log"), Path.Combine(LocalStateDir, "dashboard-error.log") },
            "update" => new[] { Path.Combine(LocalStateDir, "hermes-update.log") },
            _ => Array.Empty<string>()
        };
        return ReadTail(candidates, maxChars);
    }

    public void OpenUrl()
    {
        OpenPath(BaseUrl);
    }

    public void OpenRepo()
    {
        OpenPath(RepoRoot);
    }

    public void OpenLocalLogs()
    {
        Directory.CreateDirectory(LocalStateDir);
        OpenPath(LocalStateDir);
    }

    public void OpenHermesLogs(string hermesHome)
    {
        if (string.IsNullOrWhiteSpace(hermesHome))
        {
            hermesHome = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".hermes");
        }
        var path = Path.Combine(hermesHome, "logs");
        Directory.CreateDirectory(path);
        OpenPath(path);
    }

    public static void OpenPath(string path)
    {
        var startInfo = new ProcessStartInfo
        {
            FileName = path,
            UseShellExecute = true
        };
        Process.Start(startInfo);
    }

    public string ReadGatewayLog(string hermesHome, int maxChars = 24000)
    {
        if (string.IsNullOrWhiteSpace(hermesHome))
        {
            hermesHome = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".hermes");
        }
        return ReadTail(new[] { Path.Combine(hermesHome, "logs", "gateway.log") }, maxChars);
    }

    private async Task PostAsync(string path, CancellationToken cancellationToken)
    {
        using var response = await _http.PostAsync($"{BaseUrl}{path}", content: null, cancellationToken);
        response.EnsureSuccessStatusCode();
    }

    private string ScriptPath(string name)
    {
        var path = Path.Combine(RepoRoot, "scripts", "windows", name);
        if (!File.Exists(path))
        {
            throw new FileNotFoundException($"Missing Windows script: {path}", path);
        }
        return path;
    }

    private static void StartPowerShell(string arguments, bool hidden)
    {
        var startInfo = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            Arguments = arguments,
            UseShellExecute = true,
            WorkingDirectory = Environment.CurrentDirectory,
            WindowStyle = hidden ? ProcessWindowStyle.Hidden : ProcessWindowStyle.Normal
        };
        Process.Start(startInfo);
    }

    private static string ReadTail(IEnumerable<string> paths, int maxChars)
    {
        var parts = new List<string>();
        foreach (var path in paths)
        {
            if (!File.Exists(path))
            {
                parts.Add($"[{path}] 文件不存在");
                continue;
            }
            try
            {
                var text = File.ReadAllText(path);
                if (text.Length > maxChars)
                {
                    text = text[^maxChars..];
                }
                parts.Add($"== {path} =={Environment.NewLine}{text}");
            }
            catch (Exception ex)
            {
                parts.Add($"[{path}] {ex.Message}");
            }
        }
        return string.Join($"{Environment.NewLine}{Environment.NewLine}", parts);
    }

    private static string? GetString(JsonElement root, string name)
    {
        return root.TryGetProperty(name, out var value) && value.ValueKind != JsonValueKind.Null
            ? value.GetString()
            : null;
    }

    private static bool GetBool(JsonElement root, string name)
    {
        return root.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.True;
    }

    private static int? GetInt(JsonElement root, string name)
    {
        if (!root.TryGetProperty(name, out var value) || value.ValueKind == JsonValueKind.Null)
        {
            return null;
        }
        return value.ValueKind == JsonValueKind.Number && value.TryGetInt32(out var parsed)
            ? parsed
            : null;
    }
}
