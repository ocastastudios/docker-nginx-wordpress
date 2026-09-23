#!/bin/bash
# Fail loudly: a missing language pack must stop the build rather than
# silently shipping an image with the locale absent.
set -euo pipefail

if [ "$#" -eq 0 ]; then
  echo "Usage: $0 <language_code> <language_code>..."
  exit 1
fi

languages_array=("$@")

cd /var/www/html/web/app/
WP_VERSION=$(grep "wp_version =" ../wp/wp-includes/version.php | cut -d"'" -f2)
if [ -z "${WP_VERSION}" ]; then
  echo "Could not determine WP_VERSION"
  exit 1
fi
mkdir -p languages
cd languages
for language in "${languages_array[@]}"; do
  echo "Download language ${language} for ${WP_VERSION}"
  # -f turns an HTTP error (e.g. a 404 for a not-yet-published pack) into a non-zero exit
  if ! curl -fsSL "https://downloads.wordpress.org/translation/core/${WP_VERSION}/${language}.zip" -O; then
    echo "ERROR: no ${language} language pack published for WordPress ${WP_VERSION}." >&2
    echo "       Pin it to the newest available version in the Dockerfile, as is_IS/th/zh_TW are." >&2
    exit 1
  fi
  unzip -q "${language}.zip"
  rm "${language}.zip"
done
chown -R www-data:www-data /var/www/html/web/app/languages/
