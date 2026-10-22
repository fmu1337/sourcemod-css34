# Generated from builder/lines.json; DO NOT EDIT.
# Regenerate with: python3 builder/lines.py gen
css34_line_for_tag() {
  case "$1" in
    1.11.0.6970-mm1.10.7) printf '%s\n' sm11-oldstable ;;
    1.12.0.7253-mm1.12.0) printf '%s\n' sm12-latest ;;
    1.13.0.7472-mm1.12.0) printf '%s\n' sm13-latest ;;
    1.13.0.7404-mm1.12.0) printf '%s\n' sm13-dev ;;
    1.13.0.7404-mm2.0.0) printf '%s\n' sm13-mm20 ;;
    1.13.0.7565-mm2.0.0-khook|1.13.0.7565-mm2.0.0-khook-dhooks) printf '%s\n' sm13-mm20-khook ;;
    *) return 1 ;;
  esac
}

css34_line_has_pointer() {
  case "$1" in
    sm12-latest|sm13-latest|sm13-mm20|sm13-mm20-khook) return 0 ;;
    *) return 1 ;;
  esac
}

css34_line_can_release() {
  case "$1" in
    sm13-mm20|sm13-mm20-khook) return 1 ;;
    *) return 0 ;;
  esac
}

css34_tag_is_known_bad() {
  case "$1" in
    1.11.0.6572-mm1.10.7|1.11.0.6970-mm1.10.7|1.12.0.7239-mm1.12.0|1.12.0.7245-mm1.12.0|1.13.0.7394-mm1.12.0) return 0 ;;
    *) return 1 ;;
  esac
}
