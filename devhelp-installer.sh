#!/bin/bash

# Copyright (c) 2023 Lars Windolf <lars.windolf@gmx.de>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the “Software”), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

set -eEuo pipefail

BASE="$HOME/.local/share/custom-gtk-doc"
TMPDIR="$(mktemp -d)"

to_html() {
        dir="$1"
        name="$2"

        (
                cat <<-EOT
                <!DOCTYPE html>
                <html>
                  <head>
		    <title>$name</title>
                    <link rel="stylesheet" type="text/css" href="file:///$BASE/style.css"/>
                  </head>
                  <body>
EOT
                sed 's/{% raw %}//;s/{% endraw %}//;s/^```.*/```/;/^---/,/^---/d' "$dir/${name}.md" |\
                python3 <(cat <<EOT
import sys
import markdown
from mdx_gfm import GithubFlavoredMarkdownExtension

print(markdown.markdown(sys.stdin.read(), extensions=['mdx_gfm']))
EOT
                )
                echo "</body><html>"
        )>"$TARGETDIR/${name}.html"       
}

process() {
        PROJECT="$1"
        PROJECT_NAME="$2"
        REPO="$3"
        STARTDIR="$4"
        FIND_PATTERN="$5"
        TARGETDIR="$BASE/doc/$PROJECT"

        cd "$TMPDIR"
        echo "Cloning $REPO ..."
        git clone --depth 1 "$REPO" "$PROJECT"
        cd "$PROJECT"

        # Rename all .markdown files to .md
        while read -r f; do
                mv "$f" "${f/.markdown/}.md"
        done < <(find . -type f -name "*.markdown")

        test -d "$TARGETDIR" && find "$TARGETDIR" -delete
        mkdir -p "$TARGETDIR"

        test -f README.md && to_html . README
        cd "$STARTDIR"

        (
        cat <<-EOT
<?xml version="1.0" encoding="utf-8" standalone="no"?>
<book xmlns="http://www.devhelp.net/book" title="$PROJECT_NAME" name="$PROJECT" link="README.html">
  <chapters>
EOT

        subdirs=$(ls $FIND_PATTERN | (grep "/" || true) | sed "s/\/.*//" | sort -u)
        [ "$subdirs" = "" ] && subdirs="."
        while read subdir; do
                echo -n "$PROJECT/$STARTDIR/$subdir" >&2
                test -d "$TARGETDIR/$subdir/" || mkdir "$TARGETDIR/$subdir/"
                [ "$subdirs" != "." ] && echo "   <sub name='${subdir/*\//}' link='$subdir.html'>"

                while IFS=/ read -r dir name; do
                        echo -n "." >&2
                        echo "<sub name='${name/*\//}' link='$name.html'/>"
                        to_html "$dir" "$name"
                done < <(
                        (
                                ls ./"$subdir"/*.md | sort
                        ) | sed 's/\.md$//'
                )
                [ "$subdirs" != "." ] && echo "   </sub>"
                echo >&2
        done < <(echo "$subdirs" | sort)

        cat <<-EOT
  </chapters>
</book>
EOT
        ) >"$TARGETDIR/${PROJECT}.devhelp2"
        echo

        # Style stolen from gtk-doc style.css
        cat >"$BASE/style.css" <<-EOT
body
{
  font-family: cantarell, sans-serif;
}

code {
  background: #e6f3ff;
  border: solid 1px #729fcf;
  background: rgba(114, 159, 207, 0.1);
  border: solid 1px rgba(114, 159, 207, 0.2);
}

pre code {
  background: none !important;
  border: 0 !important;
}

pre
{
  /* tango:sky blue 0/1 */
  /* fallback for no rgba support */
  background: #e6f3ff;
  border: solid 1px #729fcf;
  background: rgba(114, 159, 207, 0.1);
  border: solid 1px rgba(114, 159, 207, 0.2);
  padding: 0.5em;
}

a, a:visited
{
  text-decoration: none;
  /* tango:sky blue 2 */
  color: #3465a4;
}
a:hover
{
  text-decoration: underline;
  /* tango:sky blue 1 */
  color: #729fcf;
}

h1, h2, h3, h4
{
  color: #555753;
  margin-top: 1em;
  margin-bottom: 1em;
}

hr
{
  /* tango:aluminium 1 */
  color: #d3d7cf;
  background: #d3d7cf;
  border: none 0px;
  height: 1px;
  clear: both;
  margin: 2.0em 0em 2.0em 0em;
}
EOT
}

FILTER="${1:-.}"
while IFS=";" read id title url startdir pattern; do
        process "$id" "$title" "$url" "$startdir" "$pattern"
done < <(
        grep "$FILTER" "$(dirname 0)/repos.txt"
)

if ! echo "$XDG_DATA_DIRS" | grep -q "$BASE"; then
        echo "Path missing in XDG_DATA_DIRS! Adding path to ~/.profile"
        echo "(Enter to confirm, Ctrl-C to cancel)"
        read dummy

        echo "export XDG_DATA_DIRS=\${XDG_DATA_DIRS}:${BASE}" >>~/.profile

        echo "~/.profile was modified. Please re-login for it to take effect!"
fi

find "$TMPDIR" -delete

nohup devhelp &
