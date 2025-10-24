#!/bin/bash
if [ "$#" -eq 0 ]; then
    echo "Usage: $0 <language_code> <language_code>..."
    exit 1
fi

languages_array=("$@")

cd /var/www/html/web/app/
WP_VERSION=$(cat ../wp/wp-includes/version.php | grep "wp_version =" | cut -d"'" -f2)
if [ -z "${WP_VERSION}" ]; then
	echo "Could not get WP_VERSION ${WP_VERSION}"
	return
fi
mkdir -p languages
cd languages
for language in "${languages_array[@]}"; do
    echo "Download language ${language} for ${WP_VERSION}"
    curl https://downloads.wordpress.org/translation/core/${WP_VERSION}/${language}.zip -O
    unzip ${language}.zip
    rm ${language}.zip
done
chown -R www-data:www-data /var/www/html/web/app/languages/
