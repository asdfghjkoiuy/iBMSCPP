#!/bin/bash
# Build a relocatable LGPL static FFmpeg for WMV/ASF preview.
# GPL and nonfree codecs stay off. Homebrew dylibs are not linked.
# aarch64 keeps assembler and NEON. The stamp covers script, config, arch, min, and compiler.
set -euo pipefail

prefix="${1:?prefix}"
cc="${2:-cc}"
arch="${3:-}"
min_version="${4:-14.0}"

version="7.1.1"
sha256="733984395e0dbbe5c046abda2dc49a5544e7e0e1e2366bba849222ae9e3a03b1"

root="$(cd "$(dirname "$0")" && pwd)"
cache_dir="${IBMS_FFMPEG_CACHE:-/tmp/ibms-ffmpeg-src}"
tarball="${cache_dir}/ffmpeg-${version}.tar.xz"
url="https://ffmpeg.org/releases/ffmpeg-${version}.tar.xz"
stamp="${prefix}/ibms-ffmpeg.stamp"

if [[ -z "${arch}" ]]; then
    arch="$(uname -m)"
fi
configure_arch="${arch}"
clang_arch="${arch}"
if [[ "${arch}" == "arm64" ]]; then
    configure_arch="aarch64"
    clang_arch="arm64"
elif [[ "${arch}" == "aarch64" ]]; then
    configure_arch="aarch64"
    clang_arch="arm64"
fi

script_sha="$(shasum -a 256 "$0" | awk '{print $1}')"
cc_id="$("${cc}" -dumpmachine)-$("${cc}" -dumpversion)"
config_id="static-lgpl;asm=on;cpu=armv8-a-on-aarch64;decoders=h263,vc1,wmv1,wmv2,wmv3;demuxers=asf,asf_o;no-audio-decoders;no-gpl"
stamp_text="version=${version} sha256=${sha256} script=${script_sha} config=${config_id} arch=${configure_arch} min=${min_version} compiler=${cc_id}"

install_notes() {
    mkdir -p "${prefix}"
    cp "${root}/COPYING.LGPLv2.1" "${prefix}/COPYING.LGPLv2.1"
    cp "${root}/LICENSE.txt" "${prefix}/LICENSE.txt"
    cp "${root}/RELINK.txt" "${prefix}/RELINK.txt"
    test -s "${prefix}/COPYING.LGPLv2.1"
}

libs_ok=1
for lib in libavcodec.a libavformat.a libavutil.a libswscale.a; do
    if [[ ! -f "${prefix}/lib/${lib}" ]]; then
        libs_ok=0
    fi
done
if [[ "${libs_ok}" -eq 1 && -f "${stamp}" && "$(cat "${stamp}")" == "${stamp_text}" && -f "${prefix}/include/libavcodec/avcodec.h" ]]; then
    install_notes
    exit 0
fi

mkdir -p "${cache_dir}" "$(dirname "${prefix}")"
if [[ ! -f "${tarball}" ]]; then
    curl -fL --retry 3 --retry-delay 2 -o "${tarball}.partial" "${url}"
    mv "${tarball}.partial" "${tarball}"
fi

digest="$(shasum -a 256 "${tarball}" | awk '{print $1}')"
if [[ "${digest}" != "${sha256}" ]]; then
    echo "ffmpeg tarball sha256 ${digest} != pinned ${sha256}" >&2
    exit 1
fi
echo "${digest}" > "${cache_dir}/ffmpeg-${version}.sha256"

cpu_flag=()
if [[ "${configure_arch}" == "aarch64" ]]; then
    cpu_flag=(--cpu=armv8-a)
fi

extra_cflags="-O2 -mmacosx-version-min=${min_version} -arch ${clang_arch}"
extra_ldflags="-mmacosx-version-min=${min_version} -arch ${clang_arch}"

work="${prefix}.build"
rm -rf "${work}"
mkdir -p "${work}"
tar -xJf "${tarball}" -C "${work}" --strip-components 1
cmp -s "${work}/COPYING.LGPLv2.1" "${root}/COPYING.LGPLv2.1"

(
    cd "${work}"
    ./configure \
        --prefix="${prefix}" \
        --cc="${cc}" \
        --arch="${configure_arch}" \
        "${cpu_flag[@]}" \
        --target-os=darwin \
        --enable-static \
        --disable-shared \
        --disable-programs \
        --disable-doc \
        --disable-debug \
        --disable-avdevice \
        --disable-avfilter \
        --disable-swresample \
        --disable-postproc \
        --disable-network \
        --disable-autodetect \
        --disable-everything \
        --disable-iconv \
        --disable-bzlib \
        --disable-lzma \
        --disable-zlib \
        --disable-securetransport \
        --disable-videotoolbox \
        --disable-audiotoolbox \
        --disable-avfoundation \
        --enable-pic \
        --enable-avcodec \
        --enable-avformat \
        --enable-avutil \
        --enable-swscale \
        --enable-protocol=file \
        --enable-demuxer=asf \
        --enable-demuxer=asf_o \
        --enable-decoder=wmv1 \
        --enable-decoder=wmv2 \
        --enable-decoder=wmv3 \
        --enable-decoder=vc1 \
        --enable-parser=vc1 \
        --extra-cflags="${extra_cflags}" \
        --extra-ldflags="${extra_ldflags}"
    if [[ "${configure_arch}" == "aarch64" ]]; then
        if ! grep -q '#define ARCH_AARCH64 1' config.h || ! grep -q '#define HAVE_NEON 1' config.h; then
            echo "aarch64 NEON was not enabled" >&2
            grep -E 'NEON|ARCH_AARCH64|HAVE_ASM|ARCH_' config.h >&2 || true
            exit 1
        fi
    fi
    # msmpeg4dec_select pulls H263. WMV1/WMV2 cannot be built without that decoder.
    actual="$(grep -E '^#define CONFIG_[A-Z0-9_]+_DECODER 1$' config_components.h | sort | sed -E 's/^#define CONFIG_([A-Z0-9_]+)_DECODER 1$/\1/')"
    expected="$(printf '%s\n' H263 VC1 WMV1 WMV2 WMV3)"
    if [[ "${actual}" != "${expected}" ]]; then
        echo "enabled decoders are not exactly H263 VC1 WMV1 WMV2 WMV3" >&2
        printf '%s\n' "${actual}" >&2
        exit 1
    fi
    if grep -E '^#define CONFIG_WMAV[0-9]_DECODER 1$' config_components.h >/dev/null; then
        echo "audio decoder enabled" >&2
        exit 1
    fi
    grep -q '#define CONFIG_WMV1_DECODER 1' config_components.h
    grep -q '#define CONFIG_WMV2_DECODER 1' config_components.h
    grep -q '#define CONFIG_ASF_DEMUXER 1' config_components.h
    grep -q '#define CONFIG_GPL 0' config.h
    grep -q '#define CONFIG_NONFREE 0' config.h
    make -j"$(sysctl -n hw.ncpu)"
    make install
    printf '%s\n' "${actual}" > "${prefix}/enabled-decoders.txt"
)

for lib in libavcodec.a libavformat.a libavutil.a libswscale.a; do
    test -f "${prefix}/lib/${lib}"
done
if [[ "${configure_arch}" == "aarch64" ]]; then
    nm_out="$(mktemp)"
    nm "${prefix}/lib/libswscale.a" > "${nm_out}"
    if ! grep -q neon "${nm_out}"; then
        echo "libswscale has no NEON symbols" >&2
        rm -f "${nm_out}"
        exit 1
    fi
    rm -f "${nm_out}"
fi
install_notes
echo "${digest}" > "${prefix}/SOURCE-SHA256.txt"
printf '%s\n' "${stamp_text}" > "${stamp}"
rm -rf "${work}"
