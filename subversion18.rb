class Subversion18 < Formula
  desc "Version control system"
  homepage "https://subversion.apache.org/"
  url "https://www.apache.org/dyn/closer.cgi?path=subversion/subversion-1.8.16.tar.bz2"
  mirror "https://archive.apache.org/dist/subversion/subversion-1.8.16.tar.bz2"
  sha256 "f18f6e8309270982135aae54d96958f9ca6b93f8a4e746dd634b1b5b84edb346"

  bottle do
    sha256 "c8e084464d3a30b65381af6cb2b225dd5511cb0f074a67a2fe6c89d66a1fae30" => :el_capitan
    sha256 "0d80b06e7c27264ff0c533ad93f9a4ff0c9702d50740c87862d1368fe2c70bc5" => :yosemite
    sha256 "2514644016e8f2a8feb77fc31b3620af91c3310cf501b8e402e3b972eef98f42" => :mavericks
  end

  option :universal
  option "with-java", "Build Java bindings"
  option "with-perl", "Build Perl bindings"
  option "with-ruby", "Build Ruby bindings"
  option "with-gnupg", "Build with support for GPG Agent"
  option "with-unicode-path", "Build with support for OS X UTF-8-MAC filename"

  deprecated_option "java" => "with-java"
  deprecated_option "perl" => "with-perl"
  deprecated_option "ruby" => "with-ruby"
  deprecated_option "unicode-path" => "with-unicode-path"

  depends_on "pkg-config" => :build

  # For Serf
  depends_on "scons" => :build
  depends_on "apr"
  depends_on "apr-util"
  depends_on "openssl@1.1"
  
  # Always build against Homebrew versions instead of system versions for consistency.
  depends_on "sqlite"

  # Other optional dependencies
  depends_on "gnupg" => :optional
  depends_on :java => :optional
  # depends_on "python" => :optional

  # Bindings require swig
  depends_on "swig" if build.with?("perl") || build.with?("python") || build.with?("ruby")

  resource "serf" do
    url "https://www.apache.org/dyn/closer.cgi?path=serf/serf-1.3.9.tar.bz2"
    mirror "https://archive.apache.org/dist/serf/serf-1.3.9.tar.bz2"
    sha256 "549c2d21c577a8a9c0450facb5cca809f26591f048e466552240947bdf7a87cc"
  end

  # Fix #23993 by stripping flags swig can't handle from SWIG_CPPFLAGS
  # Prevent "-arch ppc" from being pulled in from Perl's $Config{ccflags}
  # Prevent linking into a Python Framework
  patch :DATA

  if build.with?("perl") || build.with?("ruby")
    # If building bindings, allow non-system interpreters
    # Currently the serf -> scons dependency forces stdenv, so this isn't
    # strictly necessary
    env :userpaths

    # When building Perl or Ruby bindings, need to use a compiler that
    # recognizes GCC-style switches, since that's what the system languages
    # were compiled against.
    fails_with :clang do
      build 318
      cause "core.c:1: error: bad value (native) for -march= switch"
    end
  end

  # Patch for Subversion handling of OS X UTF-8-MAC filename.
  if build.with? "unicode-path"
    patch :p0 do
      url "https://gist.githubusercontent.com/tholu/fb5d30c586e33b53ecba/raw/a266b1aa01f95cdc38fcedda4c6bce253dfb58c2/svn_1.8.x_darwin_unicode_precomp.patch"
      sha256 "2eaee628e3161bce4b1697660281cab30f42265369bfa7074ea435e441d543e7"
    end
  end

  def install
    serf_prefix = libexec+"serf"

    resource("serf").stage do
      # SConstruct merges in gssapi linkflags using scons's MergeFlags,
      # but that discards duplicate values - including the duplicate
      # values we want, like multiple -arch values for a universal build.
      # Passing 0 as the `unique` kwarg turns this behaviour off.
      inreplace "SConstruct", "unique=1", "unique=0"

      ENV.universal_binary if build.universal?
      # scons ignores our compiler and flags unless explicitly passed
      args = %W[PREFIX=#{serf_prefix} GSSAPI=/usr CC=#{ENV.cc}
                CFLAGS=#{ENV.cflags} LINKFLAGS=#{ENV.ldflags}
                OPENSSL=#{Formula["openssl@1.1"].opt_prefix}]

      if MacOS.version >= :sierra || !MacOS::CLT.installed?
        args << "APR=#{Formula["apr"].opt_prefix}"
        args << "APU=#{Formula["apr-util"].opt_prefix}"
      end

      system "scons", *args
      system "scons", "install"
    end

    if build.with? "java"
      # Java support doesn't build correctly in parallel:
      # https://github.com/Homebrew/homebrew/issues/20415
      ENV.deparallelize

      unless build.universal?
        opoo "A non-Universal Java build was requested."
        puts <<~EOS
          To use Java bindings with various Java IDEs, you might need a universal build:
          `brew install subversion --universal --java`
        EOS
      end
    end

    ENV.universal_binary if build.universal?

    # Use existing system zlib
    # Use dep-provided other libraries
    # Don't mess with Apache modules (since we're not sudo)
    args = ["--disable-debug",
            "--prefix=#{prefix}",
            "--with-zlib=/usr",
            "--with-sqlite=#{Formula["sqlite"].opt_prefix}",
            "--with-serf=#{serf_prefix}",
            "--disable-mod-activation",
            "--disable-nls",
            "--without-apache-libexecdir",
            "--without-berkeley-db"]

    args << "--enable-javahl" << "--without-jikes" if build.with? "java"
    args << "--without-gnupg" if build.without? "gnupg"

    if MacOS::CLT.installed? && MacOS.version < :sierra
      args << "--with-apr=/usr"
      args << "--with-apr-util=/usr"
    else
      args << "--with-apr=#{Formula["apr"].opt_prefix}"
      args << "--with-apr-util=#{Formula["apr-util"].opt_prefix}"
      args << "--with-apxs=no"
    end

    if build.with? "ruby"
      args << "--with-ruby-sitedir=#{lib}/ruby"
      # Peg to system Ruby
      args << "RUBY=/usr/bin/ruby"
    end

    # If Python is built universally, then extensions built with that Python
    # are too. This default behaviour is not desired when building an extension
    # for a single architecture.
    if build.with?("python") && (which "python").universal? && !build.universal?
      ENV["ARCHFLAGS"] = "-arch #{MacOS.preferred_arch}"
    end

    # The system Python is built with llvm-gcc, so we override this
    # variable to prevent failures due to incompatible CFLAGS
    ENV["ac_cv_python_compile"] = ENV.cc

    inreplace "Makefile.in",
              "toolsdir = @bindir@/svn-tools",
              "toolsdir = @libexecdir@/svn-tools"

    system "./configure", *args
    system "make"
    system "make", "install"
    bash_completion.install "tools/client-side/bash_completion" => "subversion"

    system "make", "tools"
    system "make", "install-tools"

    if build.with? "python"
      system "make", "swig-py"
      system "make", "install-swig-py"
      (lib/"python2.7/site-packages").install_symlink Dir["#{lib}/svn-python/*"]
    end

    if build.with? "perl"
      # In theory SWIG can be built in parallel, in practice...
      ENV.deparallelize
      # Remove hard-coded ppc target, add appropriate ones
      arches = begin
        if build.universal?
          Hardware::CPU.universal_archs.as_arch_flags
        elsif MacOS.version <= :leopard
          "-arch #{Hardware::CPU.arch_32_bit}"
        else
          "-arch #{Hardware::CPU.arch_64_bit}"
        end
      end
      perl_core = Pathname.new(`perl -MConfig -e 'print $Config{archlib}'`)+"CORE"
      unless perl_core.exist?
        onoe "perl CORE directory does not exist in '#{perl_core}'"
      end

      inreplace "Makefile" do |s|
        s.change_make_var! "SWIG_PL_INCLUDES",
          "$(SWIG_INCLUDES) #{arches} -g -pipe -fno-common -DPERL_DARWIN -fno-strict-aliasing -I/usr/local/include -I#{perl_core}"
      end
      system "make", "swig-pl"
      system "make", "install-swig-pl", "DESTDIR=#{prefix}"

      # Some of the libraries get installed into the wrong place, they end up having the
      # prefix in the directory name twice.

      lib.install Dir["#{prefix}/#{lib}/*"]
    end

    if build.with? "java"
      system "make", "javahl"
      system "make", "install-javahl"
    end

    if build.with? "ruby"
      # Peg to system Ruby
      system "make", "swig-rb", "EXTRA_SWIG_LDFLAGS=-L/usr/lib"
      system "make", "install-swig-rb"
    end
  end

  def caveats
    s = <<~EOS
      svntools have been installed to:
        #{opt_libexec}
    EOS

    if build.with? "perl"
      s += <<~EOS

        The perl bindings are located in various subdirectories of:
          #{prefix}/Library/Perl
      EOS
    end

    if build.with? "ruby"
      s += <<~EOS

        You may need to add the Ruby bindings to your RUBYLIB from:
          #{HOMEBREW_PREFIX}/lib/ruby
      EOS
    end

    if build.with? "java"
      s += <<~EOS

        You may need to link the Java bindings into the Java Extensions folder:
          sudo mkdir -p /Library/Java/Extensions
          sudo ln -s #{HOMEBREW_PREFIX}/lib/libsvnjavahl-1.dylib /Library/Java/Extensions/libsvnjavahl-1.dylib
      EOS
    end

    if build.with? "unicode-path"
      s += <<~EOS
        This unicode-path version implements a hack to deal with composed/decomposed
        unicode handling on Mac OS X which is different from linux and windows.
        It is borrowed from http://subversion.tigris.org/issues/show_bug.cgi?id=2464 and
        _WILL_ break some setups. Please be sure you understand what you
        are asking for when you install this version.
      EOS
    end

    s
  end

  test do
    system "#{bin}/svnadmin", "create", "test"
    system "#{bin}/svnadmin", "verify", "test"
  end
end

__END__
diff --git a/configure b/configure
index 445251b..6ff4332 100755
--- a/configure
+++ b/configure
@@ -25366,6 +25366,8 @@ fi
 SWIG_CPPFLAGS="$CPPFLAGS"

   SWIG_CPPFLAGS=`echo "$SWIG_CPPFLAGS" | $SED -e 's/-no-cpp-precomp //'`
+  SWIG_CPPFLAGS=`echo "$SWIG_CPPFLAGS" | $SED -e 's/-F\/[^ ]* //'`
+  SWIG_CPPFLAGS=`echo "$SWIG_CPPFLAGS" | $SED -e 's/-isystem\/[^ ]* //'`



diff --git a/subversion/bindings/swig/perl/native/Makefile.PL.in b/subversion/bindings/swig/perl/native/Makefile.PL.in
index a60430b..bd9b017 100644
--- a/subversion/bindings/swig/perl/native/Makefile.PL.in
+++ b/subversion/bindings/swig/perl/native/Makefile.PL.in
@@ -76,10 +76,13 @@ my $apr_ldflags = '@SVN_APR_LIBS@'

 chomp $apr_shlib_path_var;

+my $config_ccflags = $Config{ccflags};
+$config_ccflags =~ s/-arch\s+\S+//g;
+
 my %config = (
     ABSTRACT => 'Perl bindings for Subversion',
     DEFINE => $cppflags,
-    CCFLAGS => join(' ', $cflags, $Config{ccflags}),
+    CCFLAGS => join(' ', $cflags, $config_ccflags),
     INC  => join(' ', $includes, $cppflags,
                  " -I$swig_srcdir/perl/libsvn_swig_perl",
                  " -I$svnlib_srcdir/include",

diff --git a/build/get-py-info.py b/build/get-py-info.py
index 29a6c0a..dd1a5a8 100644
--- a/build/get-py-info.py
+++ b/build/get-py-info.py
@@ -83,7 +83,7 @@ def link_options():
   options = sysconfig.get_config_var('LDSHARED').split()
   fwdir = sysconfig.get_config_var('PYTHONFRAMEWORKDIR')

-  if fwdir and fwdir != "no-framework":
+  if fwdir and fwdir != "no-framework" and sys.platform != 'darwin':

     # Setup the framework prefix
     fwprefix = sysconfig.get_config_var('PYTHONFRAMEWORKPREFIX')
