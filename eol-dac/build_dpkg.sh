#!/bin/sh

# avoid dpkg commands on /opt/arcom/bin
PATH=/usr/bin:$PATH

dpkg=eol-dac


set -e

key='<eol-prog@eol.ucar.edu>'

usage() {
    echo "Usage: ${1##*/} [-s] [-r] [dest]"
    echo "-s: sign the package files with $key"
    echo "-r: run reprepro to install .deb to dest"
    echo "dest: destination, default is ."
    exit 1
}

if [ $# -lt 1 ]; then
    usage $0
fi

dest=.
sign=false
reprepro=false
while [ $# -gt 0 ]; do
    case $1 in
    -r)
        reprepro=true
        ;;
    -s)
        sign=true
        ;;
    *)
        dest=$1
        ;;
    esac
    shift
done


script=$0
script=${script##*/}

if gitdesc=$(git describe --match "v[0-9]*"); then
    echo "git describe failed, looking for a tag of the form v[0-9]*"
    # example output of git describe: v2.0-14-gabcdef123
    gitdesc=${gitdesc/#v}       # remove leading v
    version=${gitdesc%-g*}       # 2.0-14
else
    version="1.0-1"
    # exit 1
fi

tmpdir=$(mktemp -d /tmp/${0##*/}_XXXXXX)
trap "{ rm -rf $tmpdir; }" EXIT
pdir=$tmpdir/$dpkg
mkdir -p $pdir

rsync --exclude=.gitignore -a DEBIAN usr $pdir

cat << EOD | gzip -c -9 > $pdir/usr/share/doc/$dpkg/changelog.Debian.gz
$dpkg Debian maintainer and upstream author are identical.
Therefore see also normal changelog file for Debian changes.
EOD

# output gzipped git log to usr/share/doc/eol-dac

sed -i -e "s/^Version:.*/Version: $version/" $pdir/DEBIAN/control

chmod -R g-ws $pdir/DEBIAN

fakeroot dpkg-deb -b $pdir

# dpkg-name: info: moved 'eol-dac.deb' to '/tmp/build_dpkg.sh_4RI6L9/eol-dac_1.0-1_all.deb'
newname=$(dpkg-name ${pdir%/*}/${dpkg}.deb | sed -r -e "s/.* to '([^']+)'.*/\1/")

if $sign; then
    dpkg-sig --sign builder -k "$key" $newname
fi

if $reprepro; then
    # remove _debver_all.deb from names of packages passed to reprepro
    pkg=${newname##*/}
    pkg=${pkg%_*}
    pkg=${pkg%_*}
    flock $dest sh -c "
        reprepro -V -b $dest remove jessie $pkg;
        reprepro -V -b $dest deleteunreferenced;
        reprepro -V -b $dest includedeb jessie $newname"
else
    mv $newname $dest
fi

