# Copyright 1999-2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="The reference implementation of Sass, written in Dart (built from source)"
HOMEPAGE="https://sass-lang.com/dart-sass https://github.com/sass/dart-sass"

SRC_URI="
	https://github.com/sass/dart-sass/archive/refs/tags/${PV}.tar.gz -> ${P}.tar.gz
"

S="${WORKDIR}/${P}"

LICENSE="MIT"
SLOT="0"
KEYWORDS="~amd64 ~arm64"

IUSE="doc"
# network-sandbox: extra stuff to build
# strip: The Dart standalone executable embeds its own runtime.
#        Stripping the binary can break it or remove necessary debug information,
#        so stripping is disabled for safety.
RESTRICT="network-sandbox strip"

# dart-sass is the successor to dev-ruby/sass
# has been deprecated and unsupported for a few years upstream now
# the user, adw-gtk3, has migrated to dart-sass since >=6.0
# the two have incompatible CLI options
RDEPEND="
	!dev-ruby/sass
	!dev-util/dart-sass-bin
"

BDEPEND="
	>=dev-lang/dart-3.0.0
	>=dev-util/buf-1.57.2
	dev-vcs/git
"

# Keep the packages fetched in src_unpack out of ${HOME}, which portage
# recreates on every ebuild invocation
dart_pub_env() {
	export PUB_CACHE="${WORKDIR}/.pub-cache"
}

src_unpack() {
	default
	cd "${S}" || die
	dart_pub_env

	einfo "Fetching Dart dependencies..."
	dart pub get || die "Failed to fetch Dart dependencies"

	# tool/grind/utils.dart hardcodes this path (updateLanguageRepo), and
	# buf.work.yaml expects the protobuf definition in build/language/spec
	einfo "Fetching the sass language repository..."
	git clone --depth 1 https://github.com/sass/sass.git "${S}/build/language" || \
		die "Failed to clone the sass language repository"
}

src_compile() {
	dart_pub_env

	# The language repo is already checked out in src_unpack; tell grinder not
	# to re-clone it on top of ours
	export UPDATE_SASS_SASS_REPO=false

	einfo "Building protocol buffers..."
	# Run grind.dart directly rather than via `dart run grinder`: the latter
	# forwards output through a bootstrap that exit()s without waiting for the
	# child's stdout/stderr to flush, so build errors can be lost
	dart run tool/grind.dart protobuf || die "Failed to build protocol buffers"

	einfo "Compiling dart-sass to native executable..."
	# bin/sass.dart and lib/src/embedded/isolate_dispatcher.dart read these via
	# String.fromEnvironment; without them `sass --version` and the embedded
	# protocol handshake are broken, as the fallback path (reading pubspec.yaml
	# relative to package:sass/) cannot work in an AOT executable
	local protocol_version
	protocol_version="$(<build/language/spec/EMBEDDED_PROTOCOL_VERSION)" || die
	# An empty define still compiles cleanly, so fail loudly instead of
	# shipping a binary that reports no protocol version
	[[ -n ${protocol_version} ]] || die "Failed to read EMBEDDED_PROTOCOL_VERSION"

	local -a defines=(
		-Dversion="${PV}"
		-Dcompiler-version="${PV}"
		-Dprotocol-version="${protocol_version}"
	)
	dart compile exe bin/sass.dart -o sass "${defines[@]}" || \
		die "Failed to compile dart-sass"
}

src_test() {
	dart_pub_env
	export UPDATE_SASS_SASS_REPO=false

	einfo "Preparing test requirements..."
	dart run tool/grind.dart pkg-standalone-dev || die "Failed to prepare pkg-standalone-dev"
	dart run tool/grind.dart pkg-npm-dev || die "Failed to prepare pkg-npm-dev"

	einfo "Running dart-sass tests..."
	dart run test -x node || die "Tests failed"
}

src_install() {
	# Install the compiled binary
	dobin sass

	# Install documentation
	if use doc; then
		local doc_files=( README.md LICENSE CHANGELOG.md )
		for doc_file in "${doc_files[@]}"; do
			if [[ -f "${doc_file}" ]]; then
				dodoc "${doc_file}"
			fi
		done
	fi
}

pkg_postinst() {
	elog "Dart Sass has been installed and is available as 'sass'."
	elog ""
	elog "This is the reference implementation of Sass, built from source using Dart."
	elog "It replaces the deprecated Ruby implementation (dev-ruby/sass)."
	elog ""
	elog "For more information, visit: https://sass-lang.com/"
}
