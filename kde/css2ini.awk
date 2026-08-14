# Converts the CSS emitted by themes/src/main/kde/color-scheme-*.scss into a
# KDE .colors INI file.
#
#   Colors-Window {              ->  [Colors:Window]
#     BackgroundNormal: 29, 32, 33;  ->  BackgroundNormal=29,32,33
#   }                            ->  dropped
#
# Section names are looked up in a table rather than rewritten by regex, so an
# unmapped selector fails loudly instead of producing a malformed header.

BEGIN {
    SECTION["ColorEffects-Disabled"] = "[ColorEffects:Disabled]"
    SECTION["ColorEffects-Inactive"] = "[ColorEffects:Inactive]"
    SECTION["Colors-Button"]         = "[Colors:Button]"
    SECTION["Colors-Complementary"]  = "[Colors:Complementary]"
    SECTION["Colors-Header"]         = "[Colors:Header]"
    SECTION["Colors-Header-Inactive"] = "[Colors:Header][Inactive]"
    SECTION["Colors-Selection"]      = "[Colors:Selection]"
    SECTION["Colors-Tooltip"]        = "[Colors:Tooltip]"
    SECTION["Colors-View"]           = "[Colors:View]"
    SECTION["Colors-Window"]         = "[Colors:Window]"
    SECTION["General"]               = "[General]"
    SECTION["KDE"]                   = "[KDE]"
    SECTION["WM"]                    = "[WM]"
    started = 0
}

# Selector line, e.g. "Colors-Window {"
/^[A-Za-z][A-Za-z0-9-]*[ \t]*\{[ \t]*$/ {
    sel = $0
    sub(/[ \t]*\{[ \t]*$/, "", sel)
    if (!(sel in SECTION)) {
        print "css2ini: unmapped selector: " sel > "/dev/stderr"
        exit 1
    }
    if (started) print ""
    started = 1
    print SECTION[sel]
    next
}

# Declaration line, e.g. "  BackgroundNormal: 29, 32, 33;"
/^[ \t]+[A-Za-z][A-Za-z0-9_-]*[ \t]*:/ {
    line = $0
    sub(/^[ \t]+/, "", line)
    sub(/[ \t]*;[ \t]*$/, "", line)
    idx = index(line, ":")
    key = substr(line, 1, idx - 1)
    val = substr(line, idx + 1)
    sub(/^[ \t]+/, "", val)
    sub(/[ \t]+$/, "", val)
    # sassc emits "29, 32, 33"; KDE wants "29,32,33". Restricted to numeric
    # lists so a free-text value such as Name is never silently rewritten.
    if (val ~ /^[0-9, \t]+$/) {
        gsub(/,[ \t]+/, ",", val)
    }
    print key "=" val
    next
}

/^\}[ \t]*$/ { next }
/^[ \t]*$/   { next }

{
    print "css2ini: unexpected line: " $0 > "/dev/stderr"
    exit 1
}
