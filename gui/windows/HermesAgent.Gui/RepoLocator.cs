using System.IO;

namespace HermesAgent.Gui;

public static class RepoLocator
{
    public static string FindRepoRoot()
    {
        var env = Environment.GetEnvironmentVariable("HERMES_REPO_DIR");
        if (!string.IsNullOrWhiteSpace(env) && Directory.Exists(env))
        {
            return Path.GetFullPath(env);
        }

        var current = new DirectoryInfo(AppContext.BaseDirectory);
        while (current != null)
        {
            if (LooksLikeRepo(current.FullName))
            {
                return current.FullName;
            }
            current = current.Parent;
        }

        current = new DirectoryInfo(Environment.CurrentDirectory);
        while (current != null)
        {
            if (LooksLikeRepo(current.FullName))
            {
                return current.FullName;
            }
            current = current.Parent;
        }

        var localInstall = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "HermesAgent",
            "hermes-agent"
        );
        return Directory.Exists(localInstall) ? localInstall : Environment.CurrentDirectory;
    }

    private static bool LooksLikeRepo(string path)
    {
        return File.Exists(Path.Combine(path, "hermes_cli", "main.py"))
            && Directory.Exists(Path.Combine(path, "scripts", "windows"));
    }
}
