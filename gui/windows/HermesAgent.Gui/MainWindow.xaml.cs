using System.Windows;
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

        _timer = new DispatcherTimer
        {
            Interval = TimeSpan.FromSeconds(4)
        };
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
        }
        catch (Exception ex)
        {
            DetailText.Text = ex.Message;
        }
        finally
        {
            _refreshing = false;
        }
    }

    private void RenderStatus(HermesStatus status)
    {
        DashboardStatusText.Text = status.DashboardOnline
            ? $"Dashboard: online at {_client.BaseUrl}"
            : "Dashboard: offline";
        GatewayStatusText.Text = status.GatewayRunning
            ? $"Gateway: running PID {status.GatewayPid?.ToString() ?? "unknown"}"
            : "Gateway: stopped";
        VersionText.Text = $"Version: {status.Version}";
        SessionsText.Text = $"Active sessions: {status.ActiveSessions}";

        if (!status.DashboardOnline)
        {
            DetailText.Text = $"Dashboard is not reachable. {status.Error}";
            return;
        }

        DetailText.Text =
            $"Hermes home: {status.HermesHome}\n" +
            $"Config: {status.ConfigPath}\n" +
            $"Env: {status.EnvPath}\n" +
            $"Gateway state: {status.GatewayState ?? "unknown"}" +
            (string.IsNullOrWhiteSpace(status.GatewayExitReason) ? "" : $"\nLast exit: {status.GatewayExitReason}");
    }

    private async Task RefreshLogAsync()
    {
        try
        {
            if (_selectedLog == "gateway")
            {
                LogTextBox.Text = _client.ReadGatewayLog(_lastStatus?.HermesHome ?? "");
            }
            else if (_selectedLog == "update")
            {
                LogTextBox.Text = await ReadActionOrLocalLogAsync("hermes-update", "update");
            }
            else if (_selectedLog == "restart")
            {
                LogTextBox.Text = await ReadActionOrLocalLogAsync("gateway-restart", "dashboard");
            }
            else
            {
                LogTextBox.Text = _client.ReadLocalLog("dashboard");
            }
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
        var header = $"{status.Name} running={status.Running} pid={status.Pid?.ToString() ?? "-"} exit={status.ExitCode?.ToString() ?? "-"}";
        return header + Environment.NewLine + string.Join(Environment.NewLine, status.Lines);
    }

    private async void Refresh_Click(object sender, RoutedEventArgs e)
    {
        await RefreshAllAsync();
    }

    private async void StartDashboard_Click(object sender, RoutedEventArgs e)
    {
        await RunUiActionAsync("Starting dashboard...", async () =>
        {
            await _client.StartDashboardAsync();
            await Task.Delay(1800);
        });
    }

    private async void StopDashboard_Click(object sender, RoutedEventArgs e)
    {
        await RunUiActionAsync("Stopping dashboard...", async () =>
        {
            await _client.StopDashboardAsync();
            await Task.Delay(1000);
        });
    }

    private async void RestartGateway_Click(object sender, RoutedEventArgs e)
    {
        await RunUiActionAsync("Restarting gateway...", async () =>
        {
            using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(8));
            await _client.RestartGatewayAsync(cts.Token);
            _selectedLog = "restart";
        });
    }

    private async void UpdateHermes_Click(object sender, RoutedEventArgs e)
    {
        await RunUiActionAsync("Opening update terminal...", async () =>
        {
            await _client.UpdateVisibleAsync();
            _selectedLog = "update";
        });
    }

    private async Task RunUiActionAsync(string message, Func<Task> action)
    {
        HintText.Text = message;
        try
        {
            await action();
            await RefreshAllAsync();
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, ex.Message, "Hermes Agent", MessageBoxButton.OK, MessageBoxImage.Error);
        }
        finally
        {
            HintText.Text = "Ready.";
        }
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
            MessageBox.Show(this, "Port must be between 1 and 65535.", "Hermes Agent", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        _client.Port = port;
        await RefreshAllAsync();
    }

    private async void ApplyRepo_Click(object sender, RoutedEventArgs e)
    {
        var path = RepoRootBox.Text.Trim().Trim('"');
        if (!System.IO.Directory.Exists(path))
        {
            MessageBox.Show(this, "Repository path does not exist.", "Hermes Agent", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        _client.RepoRoot = path;
        await RefreshAllAsync();
    }
}
