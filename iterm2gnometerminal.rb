#!/usr/bin/env ruby
# coding: utf-8

# Convert an iterm theme to a gnome-terminal theme
# This script was put together by gizmomogwai based on https://github.com/gfiorav/gnome-terminal-material-theme.git
# See https://aamnah.com/ubuntu/create-theme-gnome-terminal-ultimate-guide for a nice article about gnome colorthemes

# No external dependencies, just builtin ruby-3.3.0 stuff

require "rexml/document"
require "securerandom"
include REXML

def convert(pairs, key)
  v = pairs.select{|k,v|k.text == key}.first[1]
  return "%02X" % (v.text.to_f * 255)
end

def profiles
  "/org/gnome/terminal/legacy/profiles:"
end
def profile_key(profile_id, key)
  "#{profiles}/:#{profile_id}/#{key}"
end

def dconf_profile(profile_id, key, value)
  dconf(profile_key(profile_id, key),  value)
end

def dconf_profile_array(profile_id, key, values)
  dconf(profile_key(profile_id, key), "[#{values.join(', ')}]")
end

def dconf_array(key, values)
  dconf(key, "[#{values.join(', ')}]")
end

def dconf(key, value)
  "dconf write #{key} \"#{value}\""
end

def get_rgb(v)
  components = v.children.select{|i|!i.instance_of?(Text)}.each_slice(2)
  red   = convert(components, "Red Component")
  green = convert(components, "Green Component")
  blue  = convert(components, "Blue Component")
  return "'##{red}#{green}#{blue}'"
end


iterm_theme = ARGV[-1]
DRY = ARGV.length > 1 && ARGV[0] == "--dry"

doc = Document.new(File.new(iterm_theme))
keys_to_export = Hash.new
keys_to_export["palette"] = Array.new(16)

doc.get_elements("/plist/dict/*").each_slice(2).each do |key, value|
  if key.text =~ /Ansi \d+ Color/
    slot  = key.text.scan(/Ansi (\d+) Color/)[0][0].to_i
    hex   = get_rgb(value)
    keys_to_export["palette"][slot] = hex
  end
  if key.text =~ /Background Color/
    hex   = get_rgb(value)
    keys_to_export["background_color"] = hex
  end
  if key.text =~ /Foreground Color/
    hex   = get_rgb(value)
    keys_to_export["foreground_color"] = hex
  end

  if key.text =~ /Bold Color/
    hex   = get_rgb(value)
    keys_to_export["bold_color"] = hex
  end
end

existing_profiles = `dconf list #{profiles}/`
                      .split("\n")
                      .select{|i|i.start_with?(":")}
                      .map{|i|{name: `dconf read #{profiles}/#{i}visible-name`.strip[1..-2], uuid: i[1..-2]}}

theme_name = File.basename(iterm_theme, ".itermcolors")

uuid = existing_profiles.select{|i|i[:name] == theme_name}.first&.dig(:uuid)

if uuid
  puts "# Found existing theme '#{theme_name}'. Updating it."
else
  puts "# Cannot find theme '#{theme_name}'. Creating it."
  uuid = SecureRandom.uuid
  existing_profiles << {name: theme_name, uuid: uuid}
end

def run(command)
  if DRY
    puts command
  else
    raise "Cannot run command '#{command}'" unless system(command)
  end
end
# Setting base colors
run dconf_profile(uuid, "foreground_color", keys_to_export["foreground_color"])
run dconf_profile(uuid, "background_color", keys_to_export["background_color"])
run dconf_profile(uuid, "bold_color", keys_to_export["bold_color"])
# Setting ansi palette colors
run dconf_profile_array(uuid, "palette", keys_to_export["palette"])
# Setting theme name
run dconf_profile(uuid, "visible-name", "'#{theme_name}'")
run dconf_profile(uuid, "use-theme-colors", "false")
# Add profile to profiles
run dconf_array("#{profiles}/list", existing_profiles.map{|i|"'#{i[:uuid][0..-1]}'"})
