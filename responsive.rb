#!/usr/bin/env ruby
require 'csv'
require 'cgi' # for HTML escaping only.

# ----------------------------------------------------------------------------------------------
# Documentation 
# ----------------------------------------------------------------------------------------------
# This script converts a tagged CSV input into a HTML page which scales to display only the most
# imporant tokens, according to a salience metric.
#
# Use
# ---
# To Run the script on the sample input, use the following test script:
#
#    ruby responsive.rb aliceout.csv token llrank responsive.html 10 200 800 vtoken
#
# Parameters
# ----------
#
#  CSV        : The CSV file to use as input
#  WORDCOL    : The column header holding content to output
#  SCORECOL   : The column header for the (numeric) salience score
#  OUTFILE    : Name of the output HTML file.
#  LEVELS     : Number of levels to use (granularity)
#  MINWIDTH   : Width to show almost nothing (in px)
#  MAXWIDTH   : Width to show everything (in px)
#  IGNORECOL  : If this column is ""/false, will not bother to process 
#               that token (but will still output it).  Used for formatting.
#
# 
# TODO
# ----
#  * Reflow content in a way that doesn't break horribly
#  * Coloured output?
#  * Automatically rank input for clearer values
#
# Attribution
# -----------
# Written by Stephen Wattam of stephenwattam.com on the 16th of Feb 2012.
#
# The show/hide method used is taken from Frankie Roberto, at 
# http://www.frankieroberto.com/responsive_text
#
# License
# -------
# As with most of my code, this can be considered open source since there's nothing special here
# Let's say GPL, v3.  Please submit any changes back to me, purely because I wish to toy with
# and improve it.
#
# ----------------------------------------------------------------------------------------------
# Configuration 
# ----------------------------------------------------------------------------------------------
# By default, show ten levels
DEFAULT_LEVELS   = 10
DEFAULT_MINWIDTH = 200
DEFAULT_MAXWIDTH = 800

# Quick hacks to get nice output from txt input
ESCAPE_HTML      = true
FIX_NEWLINES     = true

# There must be sufficient variaion in salience counts,
# Consider that there ought to be a difference between the levels,
# so this value should be DEFAULT_LEVELS * the smallest meaningful
# difference between saliences.
MINIMUM_SENSITIVITY = 0.001

# Output constants
HTML_HEADER = "<html><head><title></title>%s</head><body>"
CSS_HEADER = "<style type=\"text/css\">"
CSS_FOOTER = "</style>"
HTML_FOOTER = "</body></html>"

# Convenience for the minmax lists
MIN = 0
MAX = 1

# ----------------------------------------------------------------------------------------------
# Input
# ----------------------------------------------------------------------------------------------
if ARGV.length < 3
  puts "USAGE: #{$0} CSV WORDCOL SCORECOL [OUTFILE] [LEVELS] [MINWIDTH] [MAXWIDTH] [IGNORECOL]"
  puts ""
  puts "Parameters"
  puts "----------"
  puts " CSV        : The CSV file to use as input"
  puts " WORDCOL    : The column header holding content to output"
  puts " SCORECOL   : The column header for the (numeric) salience score"
  puts " OUTFILE    : Name of the output HTML file."
  puts " LEVELS     : Number of levels to use (granularity)"
  puts " MINWIDTH   : Width to show almost nothing (in px)"
  puts " MAXWIDTH   : Width to show everything (in px)"
  puts " IGNORECOL  : If this column is \"\"/false, will not bother to process"
  puts "              that token (but will still output it).  Used for formatting."
  exit(1)
end

# Load the working variables
csv_in        = ARGV[0]
word_col      = ARGV[1]
salience_col  = ARGV[2]

# Optional args
html_out      = ARGV[3] == nil ? "responsive.html" : ARGV[3]
levels        = ARGV[4] == nil ? DEFAULT_LEVELS : ARGV[4].to_i
wdmm          = [] # Width min-max
wdmm[MIN]     = ARGV[5] == nil ? DEFAULT_MINWIDTH : ARGV[5].to_i
wdmm[MAX]     = ARGV[6] == nil ? DEFAULT_MAXWIDTH : ARGV[6].to_i
ignore_col    = ARGV[7]


# ----------------------------------------------------------------------------------------------
# Salience range calculation
# ----------------------------------------------------------------------------------------------
# Determine the range of salience measures
lvmm = [] # min, max
count  = 0
# Load all salience measures
puts "Reading CSV (tokens: #{word_col}, salience: #{salience_col}, ignore: #{(ignore_col) ? ignore_col : "<not specified>"})"
CSV.foreach(csv_in, {:headers => true}){|csv|
  l = csv.field(salience_col).to_f
  lvmm[MIN] = l if not lvmm[MIN] 
  lvmm[MAX] = l if not lvmm[MAX] 
  lvmm[MIN] = [lvmm[MIN], l].min
  lvmm[MAX] = [lvmm[MAX], l].max
  count += 1
}
range = lvmm[MAX] - lvmm[MIN]



# If there isn't enough variation, tell the user and quit
if range < MINIMUM_SENSITIVITY 
  puts "The salience values read have insufficient range to slice up meaningfully (< #{MINIMUM_SENSITIVITY})"
  puts "Perhaps try transforming them or something?"
  exit(1)
end

# Some nice output for the little userinos.
puts "Read #{count} rows."
puts "Range for salience: #{range.round(2)} (#{lvmm[MIN].round(2)}, #{lvmm[MAX].round(2)})"


# ----------------------------------------------------------------------------------------------
# HTML Generation
# ----------------------------------------------------------------------------------------------
# Generate the various levels
# returns a salience level of a lower resolution (0-(levels-1)).
# FIXME: fix fairly rare case where this outputs levels when salience == minmax[MAX]
def salience_to_level(levels, minmax, salience)
  salience -= minmax[MIN]
  step = (minmax[MAX] - minmax[MIN]) / levels
  return (salience/step).to_i
end

# Construct a class name for each level
def class_name(level)
  return "lv#{level}"
end

# Generate CSS media rules
def gen_css(levels, minmax)
  # Header
  css  = CSS_HEADER

  # Disable everything to start with  
  levels.times{|l|
    css += "\n.#{class_name(l)}{ display: none; }"
  }
  
  # Compute the various widths' display rules
  step = (minmax[MAX] - minmax[MIN]) / levels
  levels.times{|x|
    css += "\n@media (min-width: #{ x*step + minmax[MIN] }){"
    (x+1).times{|l|
      css += "\n.#{class_name(l)}{ display: inline; }"
    }
    css += "\n}"
  }

  # Return with the end <script>
  return css + CSS_FOOTER
end

# Adjust levels to match expectations by increasing step by one level, and adding a level
# TODO: this is sort of a hack, but it's a nice warm fuzzy-feeling one.
wdmm[MAX] += (wdmm[MAX] - wdmm[MIN]) / levels
levels    += 1

# Write output
puts "Writing output to #{html_out}..."
File.open(html_out, 'w'){|fout|
  fout << HTML_HEADER % gen_css(levels, wdmm)

  CSV.foreach(csv_in, {:headers => true}){|cin|
    # Read from csv
    salience = cin.field(salience_col).to_f
    content  = cin.field(word_col)
    ignore   = (ignore_col) ? cin.field(ignore_col).length == 0 : true
   
    # Preprocess content
    content = CGI.escapeHTML(content) if ESCAPE_HTML
    content.gsub!("\n", "<br>")       if FIX_NEWLINES

    # Add the hide/show code if we should.
    # FIXME: This method kinda breaks flow, but for now it's ok
    if(not ignore)
      # Convert to useful stuff
      level    = salience_to_level(levels, lvmm, salience)
      segment  = "<span class=\"#{class_name(level)}\">#{content}</span>"
    else
      segment = "#{content}"
    end
    # Write, with a debug \n for readability.
    fout << "\n#{segment}"
  }

  fout << HTML_FOOTER
}

# Farewell!
puts "Done."
