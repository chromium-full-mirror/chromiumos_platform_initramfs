#!/bin/sh
# Copyright 2020 The Chromium OS Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
#
# This consists of functions sourced by the /init script and used
# exclusively for recovery images.  Note that this code uses the
# busybox shell (not bash, not dash).

SCREENS=/etc/screens
LOCALES_TXT=/etc/locales.txt
LANGDIR=

# Message screens are presented in one of three boxes:
# + The 'instructions' box is used for messages telling users
#   what they can or should do.  It's for messages like "here's how
#   to cancel", or "don't turn off your computer".
# + The 'progress' box is used for to inform users how things are
#   going.  It's for animations and messages that describe what
#   work is being done, or to show percentage completion of an
#   operation.
# + The 'devmode' box is for messages that should only occur in
#   developer mode, or on non-chrome hardware.
#
# The boxes are assigned locations on the screen, top to bottom in
# the order cited above.  The locations are selected so that the
# box ensemble is centered horizontally and vertically.

# Common color codes
MENU_UI_BLACK="0x202124"
MENU_UI_GREY="0x3F4042"
MENU_UI_BLUE="0x8AB4F8"
BACKGROUND="${MENU_UI_BLACK}"

# Initialized in message_startup()
FRECON_SCALING_FACTOR=
CANVAS_SIZE=

BUTTON_HEIGHT=60  # box height plus padding

# Default width of screens/{lang}/*.png, used in most messages except buttons
DEFAULT_MESSAGE_WIDTH=720

BUTTON_WIDTH=200

# User visible message overlaid on the screen. Only use for debug features!
log() {
  echo "$@" | tee -a "${TTY_CONSOLE}" "${TTY_LOG}"
}

# Like log() but with printf() semantics.
logf() {
  printf "$@" | tee -a "${TTY_CONSOLE}" "${TTY_LOG}"
}

# Debug messages logged to VT1 and log file.
dlog() {
  echo "$@" > "${TTY_LOG}"
}

# Like dlog() but with printf() semantics.
dlogf() {
  printf "$@" > "${TTY_LOG}"
}

clear_console() {
  clear >"${TTY_CONSOLE}"
}

read_vpd_locale() {
  local region

  region="$(vpd -g region)"
  if [ -n "${region}" ]; then
    # Lookup correct value from locale list.
    sed -nre "s/^${region}\t(.*)$/\1/p" "${LOCALES_TXT}"
  else
    # Legacy devices that do not have 'region' and may have multiple locales.
    vpd -g initial_locale | sed 's/,.*//'
  fi
}

select_locale() {
  # The region (fetched via VPD) is only available on Chrome systems.
  is_nonchrome || LANGDIR="$(read_vpd_locale)"
  if [ -z "${LANGDIR}" -o ! -d "${SCREENS}/${LANGDIR}" ]; then
    dlog "initial locale '${LANGDIR}' not found"
    LANGDIR=en-US
  fi
  dlog "selected locale ${LANGDIR}"
}

# Draws text in the center of the screen.
#
# Arg 1:  The string to draw
showtext() {
  local monospace_line_height=19
  local monospace_glyph_width=10
  local text="$1"
  local text_start_h="$2"
  local glyph_offset_h="$2"
  local glyph_offset_v="$3"
  local color="$4"
  local glyph_dir="${SCREENS}/glyphs/${color}"

  for char in $(printf "%s" "${text}" | hexdump -v -e '/1 "%i "'); do
    local glyph_image="${glyph_dir}/${char}.png"

    if [ "${char}" -eq 10 ]; then
      glyph_offset_v="$(( glyph_offset_v + monospace_line_height ))"
      glyph_offset_h="${text_start_h}"
    else
      showimage "${glyph_image}" "${glyph_offset_h}" "${glyph_offset_v}"
      glyph_offset_h="$(( glyph_offset_h + monospace_glyph_width ))"
    fi
  done
}

# Encapsulate displaying of images into single function.
#
# Arg 1:  the path to the image file
# Arg 2:  a pair of numbers X,Y representing offset from center
showimage() {
  local image="$1"
  local x="$2"
  local y="$3"

  printf "\033]image:file=%s;offset=%s;scale=%d\033\\" \
    "${image}" "${x},${y}" "${FRECON_SCALING_FACTOR}" \
    > "${TTY_CONSOLE}"
  }

# Draw a single color box on the specified position
# Y-coordinate.
#
# Arg 1:  X,Y coordinate
# Arg 2:  W,H size
# Arg 3:  color
showbox() {
  local offset_x="$1"
  local offset_y="$2"
  local size_x="$3"
  local size_y="$4"
  local color="$5"

  if [ "${size_x}" -lt 1 ]; then
    size_x=1
  fi
  if [ "${size_y}" -lt 1 ]; then
    size_y=1
  fi

  printf \
    "\033]box:color=%s;size=%s;offset=%s\033\\" \
    "${color}" "${size_x},${size_y}" "${offset_x},${offset_y}" \
    > "${TTY_CONSOLE}"
}

showmessage() {
  local message_token="$1"
  local offset_x="$2"
  local offset_y="$3"

  # Determine the filename of the message resource. Fall back to en-US if
  # the localized version of the message is not available.
  local message_file="${SCREENS}/${LANGDIR}/${message_token}.png"
  if [ ! -f "${message_file}" ]; then
    message_file="${SCREENS}/en-US/${message_token}.png"
  fi

  showimage "${message_file}" "${offset_x}" "${offset_y}"
}

# Display a message in the "instructions" box.
#
# Arg 1:  a token identifying the message, which is used to form the
#   file name based on the current locale.
instructions() {
  local x="$(( -CANVAS_SIZE / 2 + DEFAULT_MESSAGE_WIDTH / 2 ))"
  local y="$(( -CANVAS_SIZE / 2 + 291 ))"

  showmessage "$1" "${x}" "${y}"
}

instructions_with_title() {
  local title_x="$(( -CANVAS_SIZE / 2 + DEFAULT_MESSAGE_WIDTH / 2 ))"
  local title_height=36
  local desc_height=144
  local title_y="$(( -CANVAS_SIZE / 2 + 228 + title_height / 2 ))"
  local desc_y="$(( title_y + title_height / 2 + 16 + desc_height / 2 ))"

  showmessage "title_$1" "${title_x}" "${title_y}"
  showmessage "desc_$1" "${title_x}" "${desc_y}"
}

# Handle display of a simple progress bar in the 'progress' box.
# stdin is a sequence of numbers indicating percent of progress.
# As each value is read, the progress bar is updated to reflect
# the percentage.
progress_bar() {
  local progress_increment=10
  local progress_height=4
  local incr_left=-500
  local leftmost="${incr_left}"
  local percent=""

  showbox 0 0 "$(( progress_increment * 100 ))" "${progress_height}" \
    "${MENU_UI_GREY}"

  while read -r percent; do
    local rightmost="$(( incr_left + progress_increment * percent ))"
    while [ "${leftmost}" -lt "${rightmost}" ]; do
      showbox "$(( leftmost + progress_increment / 2 ))" 0 \
        "$(( progress_increment + 2 ))" "${progress_height}" "${MENU_UI_BLUE}"
      leftmost="$(( leftmost + progress_increment ))"
    done
  done
}

clear_main_area() {
  # clearing y-coord -500 to 260, everything above footer
  showbox 0 -120 1100 760 "${BACKGROUND}"
}

clear_screen() {
  # clear whole screen
  showbox 0 -250 1100 600 "${BACKGROUND}"
  showbox 0 250 1100 600 "${BACKGROUND}"
}

# Enforce a delay on the user for security's sake.  A progress bar
# shows the time so that the impatient will not also be in the dark.
#
# Arg 1:  the wait time in seconds.
make_user_wait() {
  local seconds=$1

  # 100 updates because progress_bar wants percentages.
  local num_updates=100
  local ms_per_update="$(( (2 * 1000 * seconds / num_updates + 1) / 2 ))"
  local delay_sec="$(( ms_per_update / 1000 ))"
  local delay_ms="$(( ms_per_update % 1000 ))"
  local delay
  delay=$(printf "%d.%03d" "${delay_sec}" "${delay_ms}")

  for i in $(seq 1 "${num_updates}"); do
    sleep "${delay}"
    echo "${i}"
  done | progress_bar "$2"
}

wait_menu_input() {
  local KEY_UP=103
  local KEY_DOWN=108
  local KEY_ENTER=28

  local KEY_VOLDOWN=114
  local KEY_VOLUP=115
  local KEY_POWER=116

  local all_keys

  if evwaitkey --check --keys "${KEY_DOWN}:${KEY_UP}:${KEY_ENTER}"; then
    # arrow key/enter found, assuming clamshell
    all_keys="${KEY_DOWN}:${KEY_UP}:${KEY_ENTER}"
  else
    all_keys="${KEY_VOLDOWN}:${KEY_VOLUP}:${KEY_POWER}"
  fi

  local key
  key="$(evwaitkey --keys "${all_keys}")"

  case "${key}" in
    "${KEY_UP}"|"${KEY_VOLUP}")
      echo 'up'
      ;;
    "${KEY_DOWN}"|"${KEY_VOLDOWN}")
      echo 'down'
      ;;
    "${KEY_POWER}"|"${KEY_ENTER}")
      echo 'enter'
      ;;
    *)
      echo "${key}"
      ;;
  esac
}

showbutton() {
  local message_token="$1"
  local offset_x="$(( -CANVAS_SIZE / 2 + BUTTON_WIDTH / 2 ))"
  local offset_y="$2"
  local focused="$3"

  if [ "${focused}" -ne 0 ]; then
    showimage "${SCREENS}/btn_bg_focused.png" "${offset_x}" "${offset_y}"
    showmessage "${message_token}_focused" "${offset_x}" "$(( offset_y + 1 ))"
  else
    showimage "${SCREENS}/btn_bg.png" "${offset_x}" "${offset_y}"
    showmessage "${message_token}" "${offset_x}" "$(( offset_y + 1 ))"
  fi
}

showadvoption() {
  local message_token=$1
  local offset_h=$2
  local offset_v=$3
  local focused=$4

  if [ "${focused}" -ne 0 ]; then
    showimage "${SCREENS}/btn_bg_focused.png" "${offset_h}" "${offset_v}"
    showmessage "${message_token}_focused" "${offset_h}" "$(( offset_v + 1 ))"
  else
    showbox "${offset_h}" "${offset_v}" 200 30 "${BACKGROUND}"
    showmessage "${message_token}" "${offset_h}" "$(( offset_v + 1 ))"
  fi
}

on_error_onselect() {
  local selected_index=$1

  case "${selected_index}" in
    0)
      echo 'reboot ???'
      ;;
    1)
      message recovery_debug_options
      ;;
  esac

  return 0
}

on_error_onchange() {
  local selected_index=$1
  local btn_x="$(( -CANVAS_SIZE / 2 + BUTTON_WIDTH / 2 ))"
  local btn_y="$(( -CANVAS_SIZE / 2 + 388 ))"
  local adv_y="$(( CANVAS_SIZE / 2 - 182 ))"

  echo "message_on_error, index: ${selected_index}"
  message_base_screen
  instructions_with_title recovery_failed
  show_stepper_error

  showbutton btn_try_again "${btn_y}" "$(( selected_index == 0 ))"
  showadvoption btn_debug_options \
    "${btn_x}" "${adv_y}" \
    "$(( selected_index == 1 ))"
}

# Generic message to report an error.
message_on_error() {
  message_base_screen
  menu_event_loop 2 on_error_onchange on_error_onselect
}

menu_event_loop() {
  local menu_count=$1
  local onchange=$2
  local onselect=$3
  local selected_index=0

  while true; do
    local action

    ${onchange} "${selected_index}"

    case "$(wait_menu_input)" in
      up)
        if [ "${selected_index}" -gt 0 ]; then
          selected_index="$(( selected_index - 1 ))";
        fi
        ;;
      down)
        if [ "${selected_index}" -lt "$(( menu_count - 1 ))" ]; then
          selected_index="$(( selected_index + 1 ))";
        fi
        echo down
        ;;
      enter)
        "${onselect}" "${selected_index}"

        local exit=$?
        if [ "${exit}" -ne 0 ]; then
          return 0
        fi
        ;;
      *)
        echo "unknown key: ${action}"
        ;;
    esac
  done
}

recovery_debug_options_onselect() {
  local selected_index=$1

  case "${selected_index}" in
    0)
      # TODO: error page not implemented, save_log_files does not return errors
      save_log_files
      echo 'copy log'
      ;;
    1)
      message_view_log title_recovery_log /var/log/recovery.log
      ;;
    2)
      message_view_log title_message_log /var/log/messages
      ;;
    3)
      clear_screen
      return 1
      ;;
  esac

  return 0
}

recovery_debug_options_onchange() {
  local selected_index=$1
  local text_x="$(( -CANVAS_SIZE / 2 + DEFAULT_MESSAGE_WIDTH / 2 ))"
  local title_y="$(( -CANVAS_SIZE / 2 + 228 + 18 ))"

  echo "message_debug_options, index: ${selected_index}"

  message_base_screen
  showmessage title_debug_options "${text_x}" "${title_y}"

  local btn_y="$(( title_y + 18 + 40 ))" # padding 40
  showmessage tip_copy_logs "${text_x}" "${btn_y}"
  btn_y=$(( btn_y + 48 ))
  showbutton btn_copy_logs "${btn_y}" "$(( selected_index == 0 ))"
  btn_y=$(( btn_y + BUTTON_HEIGHT + 50 ))

  showmessage tip_view_logs "${text_x}" "${btn_y}"
  btn_y=$(( btn_y + 48 ))
  showbutton btn_recovery_log "${btn_y}" "$(( selected_index == 1 ))"
  btn_y=$(( btn_y + 38 ))
  showbutton btn_message_log "${btn_y}" "$(( selected_index == 2 ))"
  btn_y=$(( btn_y + 38 ))
  showbutton btn_back "${btn_y}" "$(( selected_index == 3 ))"
}

message_recovery_debug_options() {
  menu_event_loop 4 recovery_debug_options_onchange \
    recovery_debug_options_onselect
}

# variables shared between log related functions
LOG_PAGE_WIDTH=90
LOG_PAGE_HEIGHT=15
log_path=
log_line_pos=1
log_num_lines=

update_log_area() {
  local txt

  # clear old texts
  showbox 0 -20 "${CANVAS_SIZE}" 360 "${BACKGROUND}"

  # assume 100x10
  txt=$(sed "${log_line_pos},+$(( LOG_PAGE_HEIGHT - 1 )) !d" "${log_path}" \
    | cut -c "1-${LOG_PAGE_WIDTH}")
  showtext "${txt}" "$(( -CANVAS_SIZE / 2 + 5 ))" -192 'white'
}

view_log_onselect() {
  local selected_index=$1

  case "${selected_index}" in
    0)
      log_line_pos="$(( log_line_pos - LOG_PAGE_HEIGHT ))"
      if [ "${log_line_pos}" -lt 1 ]; then
        log_line_pos=1
      fi
      update_log_area
      ;;
    1)
      log_line_pos="$(( log_line_pos + LOG_PAGE_HEIGHT ))"
      if [ "${log_line_pos}" -gt "${log_num_lines}" ]; then
        log_line_pos="${log_num_lines}"
      fi
      update_log_area
      ;;
    2)
      clear_screen
      return 1
      ;;
  esac
  return 0
}

view_log_onchange() {
  local selected_index=$1
  local btn_y_begin=190

  showbutton btn_page_up "${btn_y_begin}" "$(( selected_index == 0 ))"
  showbutton btn_page_down "$(( btn_y_begin + BUTTON_HEIGHT ))" \
    "$(( selected_index == 1 ))"
  showbutton btn_back "$(( btn_y_begin + BUTTON_HEIGHT * 2 ))" \
    "$(( selected_index == 2 ))"
}

message_view_log() {
  local title_x="$(( -CANVAS_SIZE / 2 + DEFAULT_MESSAGE_WIDTH / 2 ))"
  local title_y=-285

  title=$1
  log_path=$2
  log_line_pos=1
  log_num_lines=$(wc -l "${log_path}")

  clear_screen
  showmessage "${title}" "${title_x}" "${title_y}"
  update_log_area
  menu_event_loop 3 view_log_onchange view_log_onselect
}

# First message we display at start up.
#
# This message also appears when booting factory images.
message_startup() {
  local resolution
  resolution="$(frecon-lite --print-resolution)"
  local x_res="${resolution% *}"
  local y_res="${resolution#* }"

  if [ "${x_res}" -le "${y_res}" ]; then
    # for tablet mode, add 20px margin for left and right edge.
    CANVAS_SIZE="$(( x_res - 40 ))"
  else
    CANVAS_SIZE="${y_res}"
  fi

  if [ "${x_res}" -ge 1920 ]; then
    FRECON_SCALING_FACTOR=0
  else
    FRECON_SCALING_FACTOR=1
  fi

  frecon-lite --enable-vt1 --daemon --no-login --enable-gfx \
    --enable-vts --scale="${FRECON_SCALING_FACTOR}" \
    --clear "${BACKGROUND}" --pre-create-vts \
    /dev/null
  printf "\033]input:off\a" > "${TTY_CONSOLE}"
}

# not used, was smething like
# "hold power button 8 seconds to cancel"
message_validate() {
  :
}

# Tell the user the system developer mode switch is on.
message_developer_image() {
  message_base_screen
  instructions unverified
  show_stepper_in_progress
}

# Tell the user that they must endure the 5 minute wait for a
# developer key change.
message_key_change() {
  message_base_screen
  instructions key_change
  show_stepper_in_progress
  make_user_wait 300
}

# Announce that recovery is about to start. Start the moving box animation that
# will persist until recovery is complete.
message_recovery_start() {
  message_base_screen
  instructions recovering
  show_stepper_in_progress
}

# not used
# Announce that enhanced disk wipe is started.
message_disk_wipe_start() {
  :
}

# not used
# Kill the spinner for disk wipe.
message_disk_wipe_end() {
  :
}

message_recovery_complete() {
  message_base_screen
  instructions_with_title recovery_complete
  show_stepper_done
}

# The same as message_recovery_complete, but with a different message notifying
# the user that their computer will automatically restart.
message_recovery_complete_noninteractive() {
  message_base_screen
  instructions complete_noninteractive
  show_stepper_done
  make_user_wait 10
}

# Kill the spinner animation and announce that recovery is
# complete and enhanced disk wipe is successful.
message_recovery_complete_wipe_successful() {
  message_base_screen
  instructions recovery_complete_wipe_success
  show_stepper_done
}


# Kill the spinner animation and announce that recovery is
# complete and enhanced disk wipe is failed.
message_recovery_complete_wipe_fail() {
  message_base_screen
  instructions recovery_complete_wipe_fail
  show_stepper_error
}


# Kill the spinner animation and inform user that an error occured
# during recovery but enhanced disk wipe is successful.
message_recovery_error_wipe_fail() {
  message_base_screen
  instructions recovery_error_wipe_fail
  show_stepper_error
}

# Kill the spinner animation and inform user that an error occured
# during both recovery and enhanced disk wipe.
message_recovery_error_wipe_success() {
  message_base_screen
  instructions recovery_error_wipe_success
  show_stepper_error
}

# Warn the user that the current image, although valid for
# unverified boot, won't boot if verification is re-enabled.
message_warn_invalid_install_kernel() {
  message_base_screen
  instructions dev_invalid_kernel
  show_stepper_error
}

# Tell the user that the image on the recovery media can't be
# installed, either because it failed verification, or because
# the version is out of date.
#
# This is an error condition equivalent to on_error, below.
message_invalid_install_kernel() {
  message_base_screen
  instructions invalid_kernel
  show_stepper_error
  save_log_files
  sleep 1d
  exit 1
}

# Tell the user that installation can't continue because the device
# owner has engaged developer mode blocking, and the image to be
# installed is not an official image.
#
# This is an error condition equivalent to on_error, below.
message_block_developer_mode() {
  message_base_screen
  instructions block_dev_mode
  show_stepper_error
  save_log_files
  sleep 1d
  exit 1
}

# Tell the user that the security module is hosed and point them to
# online resources for further information.
#
# This is an error condition equivalent to on_error, below.
message_security_module_failure() {
  message_base_screen
  instructions security_module_failure
  show_stepper_error
  save_log_files
  sleep 1d
  exit 1
}

# Tell the user that we're installing a firmware update.
message_update_firmware() {
  instructions update_firmware
  message_base_screen
  show_stepper_in_progress
}

# Tell the user that the battery is too low to install a firmware
# update and that they need to charge the device.
message_update_firmware_low_battery() {
  message_base_screen
  instructions update_firmware_low_battery
  show_stepper_error
}

# Tell the user that the battery is too low to install a firmware
# update and that we're waiting for the battery to charge.
message_update_firmware_low_battery_charging() {
  message_base_screen
  instructions update_firmware_low_battery_charging
  show_stepper_error
}

# Terminate with an error message.  We don't want to do anything
# else (like start a shell) because it would be trivially easy to
# get here (just unplug the USB drive after the kernel starts but
# before the USB drives are probed by the kernel) and starting a
# shell here would be a BIG security hole.
# Also if enhanced disk wipe is executed, report its result to user.
on_error() {
  if [ -n "${DISK_WIPE_RESULT}" ]; then
    if [ "${DISK_WIPE_RESULT}" -eq 0 ]; then
      message recovery_error_wipe_success
    else
      message recovery_error_wipe_fail
    fi
  else
    message on_error
  fi
  save_log_files
  sleep 1d
  exit 1
}

show_stepper() {
  # the icon real size is 24x24, but it occupies a 36x36 block.
  # use 36 here for simplicity.
  local icon_size=36
  local separator_length=46
  local padding=6

  local stepper_x="$(( -CANVAS_SIZE / 2 + icon_size / 2 ))"
  local stepper_x_step="$(( icon_size + separator_length + padding * 2 ))"
  local stepper_y="$(( 152 - CANVAS_SIZE / 2 ))"
  local separator_x="$(( -CANVAS_SIZE / 2 + icon_size + padding + \
    separator_length / 2 ))"
  local separator_color="${MENU_UI_GREY}"

  showimage "${SCREENS}/ic_$1.png" "${stepper_x}" "${stepper_y}"
  showimage "${SCREENS}/ic_$2.png" \
    "$(( stepper_x + stepper_x_step ))" "${stepper_y}"
  showimage "${SCREENS}/ic_$3.png" \
    "$(( stepper_x + stepper_x_step * 2 ))" "${stepper_y}"

  showbox "${separator_x}" "${stepper_y}" "${separator_length}" 1 \
    "${separator_color}"
  showbox "$(( separator_x + stepper_x_step ))" "${stepper_y}" \
    "${separator_length}" 1 \
    "${separator_color}"
}

show_stepper_done() {
  show_stepper 'done' 'done' 'done'
}

show_stepper_error() {
  show_stepper 'done' 'done' 'stepper_error'
}

show_stepper_in_progress() {
  show_stepper 'done' 'done' '3-done'
}

# args offset, message
show_string_locale() {
  local offset_x="$1"
  local offset_y="$2"
  local message_token="$3"

  # Determine the filename of the message resource. Fall back to en-US if
  # the localized version of the message is not available.
  local message_file="${SCREENS}/${LANGDIR}/${message_token}.png"
  if [ ! -f "${message_file}" ]; then
    message_file="${SCREENS}/en-US/${message_token}.png"
  fi

  showimage "${message_file}" "${offset_x}" "${offset_y}"
}

show_footer() {
  local qr_code_size=86
  local qr_code_x="$(( -CANVAS_SIZE / 2 + qr_code_size / 2 ))"
  local qr_code_y="$(( CANVAS_SIZE / 2 - 56 - qr_code_size / 2 ))"

  local seperator_x=-130
  local seperator_y="${qr_code_y}"

  local footer_line_height=18
  local footer_y="$(( CANVAS_SIZE / 2 - 56 - qr_code_size + 9 ))"
  local footer_left_x="$(( qr_code_x + qr_code_size / 2 + 16 + \
      DEFAULT_MESSAGE_WIDTH / 2 ))"
  local footer_right_x="$(( seperator_x + 32 + DEFAULT_MESSAGE_WIDTH / 2 ))"

  show_string_locale "${footer_left_x}" "${footer_y}" footer_left_1
  show_string_locale "${footer_left_x}" \
    "$(( footer_y + footer_line_height * 2 + 14 ))" footer_left_2
  show_string_locale "${footer_left_x}" \
    "$(( footer_y + footer_line_height * 3 + 14 ))" footer_left_3
  show_string_locale "${footer_right_x}" "${footer_y}" footer_right_1
  show_string_locale "${footer_right_x}" \
    "$(( footer_y + footer_line_height + 8 ))" footer_right_2_clamshell
  showimage "${SCREENS}/qr_code.png" "${qr_code_x}" "${qr_code_y}"
  showtext "$(crossystem hwid)" \
    "$(( qr_code_x + qr_code_size / 2 + 16 + 5 ))" \
    "$(( footer_y + footer_line_height ))" grey
  showbox "${seperator_x}" "${seperator_y}" 1 "${qr_code_size}" \
    "${MENU_UI_GREY}"
}

message_base_screen() {
  clear_main_area
  show_footer
}

message_recovery_in_progress() {
  message_base_screen
  instructions_with_title recovery_in_progress
  show_stepper_in_progress
}
