{ stdenv, fetchFromGitHub, runCommand, ncurses, gettext
, pkgconfig, cscope, ruby, tcl, perl, luajit
, darwin

, usePython27 ? false
, python27 ? null, python37 ? null
}:

let
  python = if usePython27
           then { pkg = python27; name = "python"; }
           else { pkg = python37; name = "python3"; };
in
assert python.pkg != null;

let
  # Building requires a few system tools to be in PATH.
  # Some of these we could patch into the relevant source files (such as xcodebuild and
  # qlmanage) but some are used by Xcode itself and we have no choice but to put them in PATH.
  # Symlinking them in this way is better than just putting all of /usr/bin in there.
  buildSymlinks = runCommand "macvim-build-symlinks" {} ''
    mkdir -p $out/bin
    ln -s /usr/bin/xcrun /usr/bin/xcodebuild /usr/bin/tiffutil /usr/bin/qlmanage $out/bin
  '';
in

stdenv.mkDerivation rec {
  name = "macvim-${version}";

  version = "8.1.1517";

  src = fetchFromGitHub {
    owner = "macvim-dev";
    repo = "macvim";
    rev = "snapshot-156";
    sha256 = "17plmqcn49gqwr1km77mkxflrg0f4sn06r3n0fbxa8zcz9zmb1q2";
  };

  enableParallelBuilding = true;

  nativeBuildInputs = [ pkgconfig buildSymlinks ];
  buildInputs = [
    gettext ncurses cscope luajit ruby tcl perl python.pkg
  ];

  patches = [ ./macvim.patch ./macvim-sparkle.patch ];

  # The sparkle patch modified the nibs, so we have to recompile them
  postPatch = ''
    for nib in MainMenu Preferences; do
      /usr/bin/ibtool --compile src/MacVim/English.lproj/$nib.nib/keyedobjects.nib src/MacVim/English.lproj/$nib.nib
    done
  '';

  configureFlags = [
      "--enable-cscope"
      "--enable-fail-if-missing"
      "--with-features=huge"
      "--enable-gui=macvim"
      "--enable-multibyte"
      "--enable-nls"
      "--enable-luainterp=dynamic"
      "--enable-${python.name}interp=dynamic"
      "--enable-perlinterp=dynamic"
      "--enable-rubyinterp=dynamic"
      "--enable-tclinterp=yes"
      "--without-local-dir"
      "--with-luajit"
      "--with-lua-prefix=${luajit}"
      "--with-${python.name}-command=${python.pkg}/bin/${python.name}"
      "--with-ruby-command=${ruby}/bin/ruby"
      "--with-tclsh=${tcl}/bin/tclsh"
      "--with-tlib=ncurses"
      "--with-compiledby=Nix"
  ];

  makeFlags = ''PREFIX=$(out) CPPFLAGS="-Wno-error"'';

  # This is unfortunate, but we need to use the same compiler as Xcode,
  # but Xcode doesn't provide a way to configure the compiler.
  #
  # If you're willing to modify the system files, you can do this:
  #   http://hamelot.co.uk/programming/add-gcc-compiler-to-xcode-6/
  #
  # But we don't have that option.
  preConfigure = ''
    CC=/usr/bin/clang

    DEV_DIR=$(/usr/bin/xcode-select -print-path)/Platforms/MacOSX.platform/Developer
    configureFlagsArray+=(
      "--with-developer-dir=$DEV_DIR"
    )
  ''
  # For some reason having LD defined causes PSMTabBarControl to fail at link-time as it
  # passes arguments to ld that it meant for clang.
  + ''
    unset LD
  ''
  ;

  postConfigure = ''
    substituteInPlace src/auto/config.mk --replace "PERL_CFLAGS	=" "PERL_CFLAGS	= -I${darwin.libutil}/include"

    substituteInPlace src/MacVim/vimrc --subst-var-by CSCOPE ${cscope}/bin/cscope
  '';

  postInstall = ''
    mkdir -p $out/Applications
    cp -r src/MacVim/build/Release/MacVim.app $out/Applications
    rm -rf $out/MacVim.app

    rm $out/bin/*

    cp src/vimtutor $out/bin
    for prog in mvim ex vi vim vimdiff view rvim rvimdiff rview; do
      ln -s $out/Applications/MacVim.app/Contents/bin/mvim $out/bin/$prog
    done

    # Fix rpaths
    exe="$out/Applications/MacVim.app/Contents/MacOS/Vim"
    libperl=$(dirname $(find ${perl} -name "libperl.dylib"))
    install_name_tool -add_rpath ${luajit}/lib $exe
    install_name_tool -add_rpath ${tcl}/lib $exe
    install_name_tool -add_rpath ${python.pkg}/lib $exe
    install_name_tool -add_rpath $libperl $exe
    install_name_tool -add_rpath ${ruby}/lib $exe

    # Remove manpages from tools we aren't providing
    find $out/share/man \( -name eVim.1 -or -name xxd.1 \) -delete
  '';

  meta = with stdenv.lib; {
    description = "Vim - the text editor - for macOS";
    homepage    = https://github.com/macvim-dev/macvim;
    license = licenses.vim;
    maintainers = with maintainers; [ cstrahan lilyball ];
    platforms   = platforms.darwin;
  };
}
