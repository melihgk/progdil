#!/usr/bin/ruby
# encoding: utf-8

require 'yaml'
require 'erb'

SABLON = ERB.new(File.read('_templates/exam.md.erb'))

def yaml2markdown sinav, sinav_markdown
  File.open(sinav_markdown, "w") do |f|
    f.puts "# #{sinav['title']}"
    sinav['q'].collect do |soru|
      f.puts "- #{File.read("_includes/q/#{soru}")}\n"
      f.puts "![foo](_includes/q/media/foo.png)\n\n"
    end
    f.puts "#{SABLON.result}"
    f.puts "## #{sinav['footer']}"
  end
end

task :exam => [:md, :pdf]

task :md do
  puts ".....yml'den md üretliyor....."
  Dir["_exams/*.yml"].each do |yaml|
    sinav = YAML.load(File.open(yaml))
    sinav_markdown = "_exams/#{File.basename(yaml).split('.')[0]}.md"
    yaml2markdown sinav, sinav_markdown
  end
end

task :pdf do
  puts ".....md'den pdf üretliyor....."
  Dir["_exams/*.md"].each do |markdown|
    sinav_adi = "_exams/#{File.basename(markdown).split('.')[0]}"
    sh "markdown2pdf #{sinav_adi}.md > #{sinav_adi}.pdf"
  end
end
