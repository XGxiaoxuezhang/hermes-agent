using System.Diagnostics;
using System.IO;
using System.Net.Http;
using System.Text;
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

public sealed record ProviderKey(string DisplayName, string EnvKey, string? BaseUrlKey = null, string? DefaultBaseUrl = null);

public sealed class HermesClient
{
    public static readonly IReadOnlyList<ProviderKey> ProviderKeys = new[]
    {
        new ProviderKey("OpenAI", "OPENAI_API_KEY"),
        new ProviderKey("Anthropic", "ANTHROPIC_API_KEY"),
        new ProviderKey("Gemini", "GEMINI_API_KEY"),
        new ProviderKey("DeepSeek", "DEEPSEEK_API_KEY"),
        new ProviderKey("OpenRouter", "OPENROUTER_API_KEY"),
        new ProviderKey("Xiaomi MiMo", "XIAOMI_API_KEY"),
        new ProviderKey("New API / One API", "NEW_API_API_KEY", "NEW_API_BASE_URL"),
        new ProviderKey("DashScope / Qwen", "DASHSCOPE_API_KEY"),
        new ProviderKey("Kimi / Moonshot", "KIMI_API_KEY"),
        new ProviderKey("MiniMax", "MINIMAX_API_KEY"),
        new ProviderKey("GLM / Z.AI", "ZAI_API_KEY"),
        new ProviderKey("xAI", "XAI_API_KEY"),
    };

    private readonly HttpClient _http = new()
    {
        Timeout = TimeSpan.FromSeconds(3)
    };

    public int Port { get; set; } = 9119;
    public string RepoRoot { get; set; } = RepoLocator.FindRepoRoot();

    public string BaseUrl => $"http://127.0.0.1:{Port}";

    public string DefaultEnvPath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
        ".hermes",
        ".env"
    );

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

    public Task InstallOrRepairVisibleAsync()
    {
        var localScript = Path.Combine(RepoRoot, "scripts", "windows", "install-from-github.ps1");
        string args;
        if (File.Exists(localScript))
        {
            args = $"-NoProfile -ExecutionPolicy Bypass -File \"{localScript}\" -InstallDir \"{RepoRoot}\" -Port {Port} -NoOpen -Background -Force";
        }
        else
        {
            const string url = "https://raw.githubusercontent.com/XGxiaoxuezhang/hermes-agent/windows-dashboard-i18n/scripts/windows/install-from-github.ps1";
            var installDir = Path.Combine(LocalStateDir, "hermes-agent");
            var command = $"& ([scriptblock]::Create((irm '{url}'))) -InstallDir '{installDir}' -Port {Port} -NoOpen -Background -Force";
            args = $"-NoProfile -ExecutionPolicy Bypass -Command \"{command}\"";
        }
        StartPowerShell(args, hidden: false);
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

    public string GetEnvValue(string key)
    {
        var values = LoadEnvFile(DefaultEnvPath);
        return values.TryGetValue(key, out var value) ? value : "";
    }

    public void SaveProviderKey(ProviderKey provider, string apiKey, string baseUrl)
    {
        var updates = new Dictionary<string, string>
        {
            [provider.EnvKey] = apiKey.Trim()
        };
        if (!string.IsNullOrWhiteSpace(provider.BaseUrlKey))
        {
            updates[provider.BaseUrlKey] = baseUrl.Trim();
        }
        SaveEnvValues(DefaultEnvPath, updates);
    }

    public async Task SaveProviderKeyAsync(
        ProviderKey provider,
        string apiKey,
        string baseUrl,
        bool dashboardOnline,
        CancellationToken cancellationToken
    )
    {
        SaveProviderKey(provider, apiKey, baseUrl);
        if (provider.EnvKey != "NEW_API_API_KEY" || !dashboardOnline || string.IsNullOrWhiteSpace(baseUrl))
        {
            return;
        }

        var body = JsonSerializer.Serialize(new
        {
            slug = "new-api",
            name = "New API",
            base_url = baseUrl.Trim(),
            api_key = apiKey.Trim(),
            model = ""
        });
        using var content = new StringContent(body, Encoding.UTF8, "application/json");
        using var response = await _http.PutAsync($"{BaseUrl}/api/model/custom-openai-provider", content, cancellationToken);
        response.EnsureSuccessStatusCode();
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

    private static Dictionary<string, string> LoadEnvFile(string path)
    {
        var values = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        if (!File.Exists(path))
        {
            return values;
        }

        foreach (var raw in File.ReadAllLines(path))
        {
            var line = raw.Trim();
            if (line.Length == 0 || line.StartsWith("#", StringComparison.Ordinal))
            {
                continue;
            }
            var eq = line.IndexOf('=');
            if (eq <= 0)
            {
                continue;
            }
            var key = line[..eq].Trim();
            var value = line[(eq + 1)..].Trim();
            if (value.Length >= 2 && value[0] == '"' && value[^1] == '"')
            {
                value = value[1..^1];
            }
            values[key] = value;
        }
        return values;
    }

    private static void SaveEnvValues(string path, IReadOnlyDictionary<string, string> updates)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var lines = File.Exists(path)
            ? File.ReadAllLines(path).ToList()
            : new List<string>();

        foreach (var (key, rawValue) in updates)
        {
            var value = rawValue.Replace("\r", "").Replace("\n", "");
            var replacement = $"{key}={value}";
            var found = false;
            for (var i = 0; i < lines.Count; i++)
            {
                var trimmed = lines[i].TrimStart();
                if (trimmed.StartsWith($"{key}=", StringComparison.OrdinalIgnoreCase))
                {
                    lines[i] = replacement;
                    found = true;
                    break;
                }
            }
            if (!found)
            {
                lines.Add(replacement);
            }
        }

        File.WriteAllText(path, string.Join(Environment.NewLine, lines) + Environment.NewLine);
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
