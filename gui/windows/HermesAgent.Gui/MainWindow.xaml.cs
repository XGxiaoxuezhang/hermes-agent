using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Threading;

namespace HermesAgent.Gui;

public partial class MainWindow : Window
{
    private readonly HermesClient _client = new();
    private readonly DispatcherTimer _timer;
    private HermesStatus? _lastStatus;
    private string _selectedLog = "dashboard";
    private bool _refreshing;

    public MainWindow()
    {
        InitializeComponent();
        RepoRootBox.Text = _client.RepoRoot;
        ProviderCombo.ItemsSource = HermesClient.ProviderKeys;
        ProviderCombo.DisplayMemberPath = nameof(ProviderKey.DisplayName);
        ProviderCombo.SelectedIndex = 0;

        _timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(4) };
        _timer.Tick += async (_, _) => await RefreshAllAsync();
        Loaded += async (_, _) =>
        {
            _timer.Start();
            await RefreshAllAsync();
        };
    }

    private async Task RefreshAllAsync()
    {
        if (_refreshing)
        {
            return;
        }

        _refreshing = true;
        try
        {
            using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(5));
            _lastStatus = await _client.GetStatusAsync(cts.Token);
            RenderStatus(_lastStatus);
            await RefreshLogAsync();
            LastRefreshText.Text = $"已刷新 {DateTime.Now:HH:mm:ss}";
        }
        catch (Exception ex)
        {
            DetailText.Text = ex.Message;
            HintText.Text = "刷新失败。";
        }
        finally
        {
            _refreshing = false;
        }
    }

    private void RenderStatus(HermesStatus status)
    {
        PortText.Text = $"端口 {_client.Port}";
        VersionText.Text = status.Version;
        SessionsText.Text = status.ActiveSessions.ToString();

        DashboardBadgeText.Text = status.DashboardOnline ? "在线" : "离线";
        DashboardBadgeText.Foreground = Brush(status.DashboardOnline ? "#047857" : "#B42318");
        DashboardSubText.Text = status.DashboardOnline ? _client.BaseUrl : "本地后端未响应";

        GatewayBadgeText.Text = status.GatewayRunning ? "运行中" : "未运行";
        GatewayBadgeText.Foreground = Brush(status.GatewayRunning ? "#047857" : "#B42318");
        GatewaySubText.Text = status.GatewayRunning
            ? $"PID {status.GatewayPid?.ToString() ?? "未知"}"
            : "未检测到进程";

        StartButton.IsEnabled = !status.DashboardOnline;
        StopButton.IsEnabled = status.DashboardOnline;
        RestartButton.IsEnabled = status.DashboardOnline;
        InstallButton.IsEnabled = true;

        if (!status.DashboardOnline)
        {
            DetailText.Text =
                "控制台后端不可达。可以点击左侧“启动控制台后端”。\n" +
                $"最近错误：{status.Error ?? "无详细信息"}";
            FooterText.Text = "离线状态下仍可查看本地日志、启动后端或打开更新终端。";
            return;
        }

        var gatewayState = string.IsNullOrWhiteSpace(status.GatewayState) ? "未知" : status.GatewayState;
        DetailText.Text =
            $"Hermes Home：{status.HermesHome}\n" +
            $"配置文件：{status.ConfigPath}\n" +
            $"密钥文件：{status.EnvPath}\n" +
            $"网关状态：{gatewayState}" +
            (string.IsNullOrWhiteSpace(status.GatewayExitReason) ? "" : $"\n上次退出：{status.GatewayExitReason}");
        FooterText.Text = "本机模式：界面只显示密钥文件路径，不读取或展示密钥值。";
    }

    private async Task RefreshLogAsync()
    {
        try
        {
            LogTitleText.Text = LogTitle(_selectedLog);
            LogTextBox.Text = _selectedLog switch
            {
                "gateway" => _client.ReadGatewayLog(_lastStatus?.HermesHome ?? ""),
                "update" => await ReadActionOrLocalLogAsync("hermes-update", "update"),
                "restart" => await ReadActionOrLocalLogAsync("gateway-restart", "dashboard"),
                _ => _client.ReadLocalLog("dashboard")
            };
            LogTextBox.ScrollToEnd();
        }
        catch (Exception ex)
        {
            LogTextBox.Text = ex.Message;
        }
    }

    private async Task<string> ReadActionOrLocalLogAsync(string actionName, string fallback)
    {
        if (_lastStatus?.DashboardOnline != true)
        {
            return _client.ReadLocalLog(fallback);
        }

        using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        var status = await _client.GetActionStatusAsync(actionName, cts.Token);
        var running = status.Running ? "运行中" : "已结束";
        var exit = status.ExitCode?.ToString() ?? "未知";
        var header = $"{status.Name}：{running}  PID={status.Pid?.ToString() ?? "-"}  退出码={exit}";
        return header + Environment.NewLine + string.Join(Environment.NewLine, status.Lines);
    }

    private async Task RunUiActionAsync(string message, Func<Task> action)
    {
        HintText.Text = message;
        SetBusy(true);
        try
        {
            await action();
            await RefreshAllAsync();
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, ex.Message, "Hermes Agent 控制台", MessageBoxButton.OK, MessageBoxImage.Error);
        }
        finally
        {
            SetBusy(false);
            HintText.Text = "就绪";
        }
    }

    private void SetBusy(bool busy)
    {
        StartButton.IsEnabled = !busy && (_lastStatus?.DashboardOnline != true);
        StopButton.IsEnabled = !busy && (_lastStatus?.DashboardOnline == true);
        RestartButton.IsEnabled = !busy && (_lastStatus?.DashboardOnline == true);
        UpdateButton.IsEnabled = !busy;
        InstallButton.IsEnabled = !busy;
    }

    private async void Refresh_Click(object sender, RoutedEventArgs e)
    {
        await RefreshAllAsync();
    }

    private async void StartDashboard_Click(object sender, RoutedEventArgs e)
    {
        await RunUiActionAsync("正在启动控制台后端...", async () =>
        {
            await _client.StartDashboardAsync();
            await Task.Delay(1800);
        });
    }

    private async void StopDashboard_Click(object sender, RoutedEventArgs e)
    {
        await RunUiActionAsync("正在停止控制台后端...", async () =>
        {
            await _client.StopDashboardAsync();
            await Task.Delay(1000);
        });
    }

    private async void RestartGateway_Click(object sender, RoutedEventArgs e)
    {
        await RunUiActionAsync("正在重启消息网关...", async () =>
        {
            using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(8));
            await _client.RestartGatewayAsync(cts.Token);
            _selectedLog = "restart";
        });
    }

    private async void UpdateHermes_Click(object sender, RoutedEventArgs e)
    {
        await RunUiActionAsync("已打开更新终端，请在终端中查看进度。", async () =>
        {
            await _client.UpdateVisibleAsync();
            _selectedLog = "update";
        });
    }

    private async void InstallRepair_Click(object sender, RoutedEventArgs e)
    {
        await RunUiActionAsync("已打开安装/修复终端，请按终端提示等待完成。", async () =>
        {
            await _client.InstallOrRepairVisibleAsync();
            _selectedLog = "update";
        });
    }

    private async void DashboardLog_Click(object sender, RoutedEventArgs e)
    {
        _selectedLog = "dashboard";
        await RefreshLogAsync();
    }

    private async void GatewayLog_Click(object sender, RoutedEventArgs e)
    {
        _selectedLog = "gateway";
        await RefreshLogAsync();
    }

    private async void UpdateLog_Click(object sender, RoutedEventArgs e)
    {
        _selectedLog = "update";
        await RefreshLogAsync();
    }

    private async void RestartLog_Click(object sender, RoutedEventArgs e)
    {
        _selectedLog = "restart";
        await RefreshLogAsync();
    }

    private async void ApplyPort_Click(object sender, RoutedEventArgs e)
    {
        if (!int.TryParse(PortBox.Text.Trim(), out var port) || port < 1 || port > 65535)
        {
            MessageBox.Show(this, "端口必须在 1 到 65535 之间。", "Hermes Agent 控制台", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        _client.Port = port;
        HintText.Text = $"已切换到端口 {port}";
        await RefreshAllAsync();
    }

    private async void ApplyRepo_Click(object sender, RoutedEventArgs e)
    {
        var path = RepoRootBox.Text.Trim().Trim('"');
        if (!Directory.Exists(path))
        {
            MessageBox.Show(this, "仓库目录不存在。", "Hermes Agent 控制台", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        _client.RepoRoot = path;
        HintText.Text = "仓库目录已更新。";
        await RefreshAllAsync();
    }

    private void OpenRepo_Click(object sender, RoutedEventArgs e)
    {
        SafeOpen(_client.RepoRoot);
    }

    private void OpenConfig_Click(object sender, RoutedEventArgs e)
    {
        SafeOpen(_lastStatus?.ConfigPath);
    }

    private void OpenEnv_Click(object sender, RoutedEventArgs e)
    {
        SafeOpen(string.IsNullOrWhiteSpace(_lastStatus?.EnvPath) ? _client.DefaultEnvPath : _lastStatus.EnvPath);
    }

    private void OpenLogs_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            if (!string.IsNullOrWhiteSpace(_lastStatus?.HermesHome))
            {
                _client.OpenHermesLogs(_lastStatus.HermesHome);
            }
            else
            {
                _client.OpenLocalLogs();
            }
        }
        catch (Exception ex)
        {
            ShowOpenError(ex);
        }
    }

    private void CopyUrl_Click(object sender, RoutedEventArgs e)
    {
        Clipboard.SetText(_client.BaseUrl);
        HintText.Text = $"已复制：{_client.BaseUrl}";
    }

    private void OpenDashboard_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            _client.OpenUrl();
        }
        catch (Exception ex)
        {
            ShowOpenError(ex);
        }
    }

    private void ClearLog_Click(object sender, RoutedEventArgs e)
    {
        LogTextBox.Clear();
    }

    private void AutoRefresh_Changed(object sender, RoutedEventArgs e)
    {
        if (_timer is null)
        {
            return;
        }

        if (AutoRefreshBox.IsChecked == true)
        {
            _timer.Start();
            HintText.Text = "自动刷新已开启。";
        }
        else
        {
            _timer.Stop();
            HintText.Text = "自动刷新已暂停。";
        }
    }

    private void ProviderCombo_SelectionChanged(object sender, System.Windows.Controls.SelectionChangedEventArgs e)
    {
        if (ProviderCombo.SelectedItem is not ProviderKey provider)
        {
            return;
        }
        ApiKeyBox.Password = "";
        BaseUrlBox.Text = provider.BaseUrlKey is null ? "" : _client.GetEnvValue(provider.BaseUrlKey);
        BaseUrlBox.Visibility = provider.BaseUrlKey is null ? Visibility.Collapsed : Visibility.Visible;
        var existing = _client.GetEnvValue(provider.EnvKey);
        KeyStatusText.Text = string.IsNullOrWhiteSpace(existing)
            ? $"{provider.DisplayName} 尚未配置。保存后会写入 {_client.DefaultEnvPath}"
            : $"{provider.DisplayName} 已配置。重新粘贴可覆盖，留空不会改动。";
    }

    private async void SaveKey_Click(object sender, RoutedEventArgs e)
    {
        if (ProviderCombo.SelectedItem is not ProviderKey provider)
        {
            return;
        }
        var apiKey = ApiKeyBox.Password.Trim();
        if (string.IsNullOrWhiteSpace(apiKey) && string.IsNullOrWhiteSpace(_client.GetEnvValue(provider.EnvKey)))
        {
            MessageBox.Show(this, "请先粘贴 API Key。", "Hermes Agent 控制台", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }

        if (string.IsNullOrWhiteSpace(apiKey))
        {
            apiKey = _client.GetEnvValue(provider.EnvKey);
        }
        try
        {
            using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(8));
            await _client.SaveProviderKeyAsync(
                provider,
                apiKey,
                BaseUrlBox.Text,
                _lastStatus?.DashboardOnline == true,
                cts.Token
            );
            ApiKeyBox.Password = "";
            KeyStatusText.Text = $"已保存 {provider.DisplayName} 密钥。重启后端或开始新会话后生效。";
            HintText.Text = "密钥已保存。";
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, ex.Message, "保存失败", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private static string LogTitle(string key)
    {
        return key switch
        {
            "gateway" => "网关日志",
            "update" => "更新日志",
            "restart" => "重启日志",
            _ => "控制台日志"
        };
    }

    private void SafeOpen(string? path)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            MessageBox.Show(this, "当前状态里没有可打开的路径。", "Hermes Agent 控制台", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        try
        {
            HermesClient.OpenPath(path);
        }
        catch (Exception ex)
        {
            ShowOpenError(ex);
        }
    }

    private void ShowOpenError(Exception ex)
    {
        MessageBox.Show(this, ex.Message, "无法打开", MessageBoxButton.OK, MessageBoxImage.Warning);
    }

    private static SolidColorBrush Brush(string hex)
    {
        return (SolidColorBrush)new BrushConverter().ConvertFromString(hex)!;
    }
}
