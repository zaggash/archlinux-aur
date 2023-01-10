# Maintainer: Alexandre P.

pkgname=xcursor-breeze
pkgver=5.26.5 # renovate: datasource=github-tags depName=KDE/breeze
pkgrel=1
pkgdesc="Breeze cursor theme (KDE Plasma 5). This package is for usage in non-KDE Plasma desktops."
arch=('any')
url="https://github.com/KDE/breeze"
license=('GPL')
depends=('libxcursor')
conflicts=('breeze')
source=("${url}/archive/v${pkgver}.tar.gz")

package() {
  install -dm755 "$pkgdir"/usr/share/icons/
  cp -r "$srcdir"/breeze-${pkgver}/cursors/Breeze/Breeze/           "$pkgdir"/usr/share/icons/
  cp -r "$srcdir"/breeze-${pkgver}/cursors/Breeze_Snow/Breeze_Snow/ "$pkgdir"/usr/share/icons/
}
