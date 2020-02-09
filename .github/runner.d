import std;

///
struct Defines
{
static:
    /// ドキュメントジェネレータを指定します。
    /// gendocのバージョンが更新されたら変更してください。
    immutable documentGenerator = "gendoc@0.0.4";
    /// テスト対象にするサブパッケージを指定します。
    /// サブパッケージが追加されたらここにも追加してください。
    immutable subPkgs = ["windows", "libdparse_usage"];
}

///
struct Config
{
    ///
    string os;
    ///
    string arch;
    ///
    string compiler;
    ///
    string archiveSuffix;
    ///
    string scriptDir = __FILE__.dirName();
    ///
    string projectName;
    ///
    string refName;
}
///
__gshared Config config;

///
int main(string[] args)
{
    string mode;

    version (Windows)      {config.os = "windows";}
    else version (linux)   {config.os = "linux";}
    else version (OSX)     {config.os = "osx";}
    else static assert(0, "Unsupported OS");

    version (Windows)      {config.archiveSuffix = ".zip";}
    else version (linux)   {config.archiveSuffix = ".tar.gz";}
    else version (OSX)     {config.archiveSuffix = ".tar.gz";}
    else static assert(0, "Unsupported OS");

    version (D_LP64)      {config.arch = "x86_64";}
    else                  {config.arch = "x86";}

    version (DigitalMars) {config.compiler = "dmd";}
    else version (LDC)    {config.compiler = "ldc2";}
    else version (GNU)    {config.compiler = "gdc";}
    else static assert(0, "Unsupported Compiler");

    config.projectName = environment.get("GITHUB_REPOSITORY").chompPrefix(environment.get("GITHUB_ACTOR") ~ "/");
    config.refName = getRefName();

    string[] exDubOpts;

    args.getopt(
        "a|arch",          &config.arch,
        "os",              &config.os,
        "c|compiler",      &config.compiler,
        "archive-suffix",  &config.archiveSuffix,
        "m|mode",          &mode,
        "exdubopts",       &exDubOpts);


    switch (mode.toLower)
    {
    case "unit-test":
    case "unittest":
    case "ut":
        unitTest(exDubOpts);
        break;
    case "integration-test":
    case "integrationtest":
    case "tt":
        integrationTest(exDubOpts);
        break;
    case "create-release-build":
    case "createreleasebuild":
    case "release-build":
    case "releasebuild":
    case "build":
        createReleaseBuild(exDubOpts);
        break;
    case "create-archive":
    case "createarchive":
        createArchive();
        break;
    case "create-document":
    case "createdocument":
    case "create-document-test":
    case "createdocumenttest":
    case "generate-document":
    case "generatedocument":
    case "generate-document-test":
    case "generatedocumenttest":
    case "gendoc":
    case "docs":
    case "doc":
        generateDocument();
        break;
    case "all":
        unitTest(exDubOpts);
        integrationTest(exDubOpts);
        createReleaseBuild(exDubOpts);
        createArchive();
        generateDocument();
        break;
    default:
        enforce(0, "Unknown mode: " ~ mode);
        break;
    }
    return 0;
}

///
void unitTest(string[] exDubOpts = null)
{
    if (!".cov".exists)
        mkdir(".cov");
    auto opt = ["-a", config.arch, "--compiler", config.compiler, "--coverage", "--main-file", ".github/ut.d"]
        ~ exDubOpts;
    string[string] env;
    if (config.os == "windows" && config.arch == "x86_64")
    {
        auto bin64dir = searchDCompiler().dirName.buildPath("../bin64");
        if (bin64dir.exists && bin64dir.isDir)
            env["Path"] = bin64dir ~ ";" ~ environment.get("Path");
    }
    exec(["dub", "test"] ~ opt, null, env);
    foreach (pkg; Defines.subPkgs)
        exec(["dub", "test", ":" ~ pkg] ~ opt, null, env);
}

///
void generateDocument()
{
    import std.file;
    string[string] env;
    if (config.os == "windows" && config.arch == "x86_64")
    {
        auto bin64dir = searchDCompiler().dirName.buildPath("../bin64");
        if (bin64dir.exists && bin64dir.isDir)
            env["Path"] = bin64dir ~ ";" ~ environment.get("Path");
    }
    exec(["dub", "run", Defines.documentGenerator, "-y", "-a", config.arch,
        "--", "-a", config.arch, "-b=release"], null, env);

    // CircleCIでgh-pagesへのデプロイがビルドエラーになる件を回避
    auto circleCiConfigDir = config.scriptDir.buildPath("../docs/.circleci");
    if (!circleCiConfigDir.exists || !circleCiConfigDir.isDir)
        mkdirRecurse(circleCiConfigDir);
    std.file.write(circleCiConfigDir.buildPath("config.yml"),`
        version: 2
          jobs:
            build:
              branches:
                ignore:
                  - gh-pages
    `.chompPrefix("\n").outdent);
}

///
void createReleaseBuild(string[] exDubOpts = null)
{
    string[string] env;
    if (config.os == "windows" && config.arch == "x86_64")
    {
        auto bin64dir = searchDCompiler().dirName.buildPath("../bin64");
        if (bin64dir.exists && bin64dir.isDir)
            env["Path"] = bin64dir ~ ";" ~ environment.get("Path");
    }
    exec(["dub", "build", "-a", config.arch, "-b=unittest-cov", "--compiler", config.compiler]
        ~ exDubOpts, null, env);
}


///
void integrationTest(string[] exDubOpts = null)
{
    string[string] env;
    if (config.os == "windows" && config.arch == "x86_64")
    {
        auto bin64dir = searchDCompiler().dirName.buildPath("../bin64");
        if (bin64dir.exists && bin64dir.isDir)
            env["Path"] = bin64dir ~ ";" ~ environment.get("Path");
    }
    auto covdir = config.scriptDir.buildNormalizedPath("../.cov").absolutePath();
    if (!covdir.exists)
        mkdirRecurse(covdir);

    // build
    exec(["dub", "build", "-a", config.arch, "-b=cov", "--compiler", config.compiler]
        ~ exDubOpts, null, env);

    // do-nothiong
}


///
void createArchive()
{
    import std.file;
    auto archiveName = format!"%s-%s-%s-%s%s"(
        config.projectName, config.refName, config.os, config.arch, config.archiveSuffix);
    scope (success)
        writeln("::set-output name=ARCNAME::", archiveName);
    version (Windows)
    {
        auto zip = new ZipArchive;
        foreach (de; dirEntries("build", SpanMode.depth))
        {
            if (de.isDir)
                continue;
            auto m = new ArchiveMember;
            m.expandedData = cast(ubyte[])std.file.read(de.name);
            m.name = de.name.absolutePath.relativePath(absolutePath("build"));
            m.time = de.name.timeLastModified();
            m.fileAttributes = de.name.getAttributes();
            m.compressionMethod = CompressionMethod.deflate;
            zip.addMember(m);
        }
        std.file.write(archiveName, zip.build());
    }
    else
    {
        string abs(string file, string base)
        {
            return file.absolutePath.relativePath(absolutePath(base));
        }
        void mv(string from, string to)
        {
            if (from.isDir)
                return;
            if (!to.dirName.exists)
                mkdirRecurse(to.dirName);
            std.file.rename(from, to);
        }
        mv("build/gendoc", "archive-tmp/bin/gendoc");
        foreach (de; dirEntries("build/ddoc", SpanMode.depth))
            mv(de.name, buildPath("archive-tmp/etc/.gendoc/ddoc", abs(de.name, "build/ddoc")));
        foreach (de; dirEntries("build/source_docs", SpanMode.depth))
            mv(de.name, buildPath("archive-tmp/etc/.gendoc/docs", abs(de.name, "build/source_docs")));
        exec(["tar", "cvfz", buildPath("..", archiveName), "-C", "."]
            ~ dirEntries("archive-tmp", "*", SpanMode.shallow)
                .map!(de => abs(de.name, "archive-tmp")).array, "archive-tmp");
    }
}

///
void exec(string[] args, string workDir = null, string[string] env = null)
{
    import std.process, std.stdio;
    writefln!"> %-(%-s %)"(args);
    auto pid = spawnProcess(args, env, std.process.Config.none, workDir ? workDir : ".");
    auto res = pid.wait();
    enforce(res == 0, format!"Execution was failed[code=%d]."(res));
}
///
string cmd(string[] args, string workDir = null, string[string] env = null)
{
    import std.process;
    auto res = execute(args, env, std.process.Config.none, size_t.max, workDir);
    enforce(res.status == 0, format!"Execution was failed[code=%d]."(res.status));
    return res.output;
}

///
string getRefName()
{
    auto ghref = environment.get("GITHUB_REF");
    enum keyBranche = "refs/heads/";
    enum keyTag = "refs/heads/";
    enum keyPull = "refs/heads/";
    if (ghref.startsWith(keyBranche))
        return ghref[keyBranche.length..$];
    if (ghref.startsWith(keyTag))
        return ghref[keyTag.length..$];
    if (ghref.startsWith(keyPull))
        return "pr" ~ ghref[keyPull.length..$];
    return cmd(["git", "describe", "--tags", "--always"]).chomp;
}

///
string searchPath(string name, string[] dirs = null)
{
    if (name.length == 0)
        return name;
    if (name.isAbsolute())
        return name;
    foreach (dir; dirs.chain(environment.get("Path").split(";")))
    {
        version (Windows)
            auto bin = dir.buildPath(name).setExtension(".exe");
        else
            auto bin = dir.buildPath(name);
        if (bin.exists)
            return bin;
    }
    return name;
}

///
string searchDCompiler()
{
    auto compiler = config.compiler;
    if (compiler.absolutePath.exists)
        return compiler.absolutePath;
    compiler = compiler.searchPath();
    if (compiler.exists)
        return compiler;

    auto dc = searchPath(environment.get("DC"));
    if (dc.exists)
        return dc;

    auto dmd = searchPath(environment.get("DMD"));
    if (dmd.exists)
        return dmd;

    return "dmd";
}