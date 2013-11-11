require 'prawn'
require 'json'

#boilerplate logging
def log text
  @logfile.write( "\r\n" + Time.new.to_s + ": " + text.to_s())
  puts text;
end
 
@logfile = File.new('novel.txt', "a")

#copied from other file....
def load_collection_from_file(filename, default)

	return default unless File.exists?(filename)
	
	file = File.new(filename, 'r');
	file_json = file.read;
	file.close;
	collection = JSON.load(file_json);
	
	log("Loaded #{collection.length} collection item(s) from #{filename}.");
	
	return collection;
end

#define database file, get phrases
@db_file = "db.dat"
@db = load_collection_from_file(@db_file, []);

#some of these were missed (space before ending punctuation), remove them now
@db.collect!{ |phrase|
	phrase.gsub(/\s*([[:punct:]]+$)/, '\1');
}

#randomize
@db.shuffle!

#"friend" count for the novel credits -- pretty print number
friends = @db.length.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse;

#use first phrase as the novel's title
the_title_one = @db.pop
#remove end punctuation
the_title_one.gsub!(/[\s[[:punct:]]]*$/, "");
#Title Case (or close enough)
the_title_one.gsub!(/\w+/) do |word|
	if(word.length > 2) then
		word.capitalize
	else
		word
	end
end

#split novel into chapters
number_chapters = 40;
#choose random points in the list of words to chop into ranges for each chapter
chapter_points = number_chapters.times.collect {
	rand(@db.length);
}

#add "0" phrase and last phrase to points list
chapter_points << 0;
chapter_points << (@db.length - 1)

#sort points and ensure no dups
chapter_points = chapter_points.uniq.sort #may reduce size, who cares
#iterate sequentially and build a collection of ranges covering all the phrases
chapter_ranges = chapter_points.each_cons(2).collect { |rng| (rng[0]...rng[1]) }

#perform a word count after joining everything. Attempt to increase accuracy
full_text = @db.join " ";
#replace most word-separating punctuation with a space
full_text.gsub!(/[,\.\!\?]/, " ");
#replace all other punctuation with nothing (like apostrophes and quotes)
full_text.gsub!(/[[:punct:]]/, "");
#count all space-delimited words
word_count = full_text.split.size
#pretty print
word_count_txt = word_count.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse;
log("Novel is about #{word_count_txt} words long.");

#build PDF
Prawn::Document.generate("novel.pdf", :page_size => "A4", :margin => 50) do |pdf|

	#you'll need to copy the basic Palatino font into this directory. Or change this.
	pdf.font_families.update("Palatino" => {
		:normal => "pala.ttf"
	})
	
	#title page
	pdf.font "Times-Roman"
	pdf.formatted_text_box [
		{:text => the_title_one, :align => :center, :size => 30},
		{:text => "\r\nBy Eli Brody and #{friends} friends", :align => :center, :size => 20},
	], :valign => :center, :align => :center, :height => 400
		
	#each "chapter" range
	chapter_ranges.each_with_index {|rng, i|
		rng_arr = rng.to_a
		frst = rng_arr[1]
		next if rng_arr.size < 2
	
		pdf.start_new_page
		pdf.font "Times-Roman"
		pdf.font_size 20
			txt = @db[(rng_arr[0])]
			txt.gsub!(/[\s[[:punct:]]]*$/, "");
			pdf.text("\r\nChapter #{i+1}: #{txt}\r\n\r\n");
		
		lst = rng_arr[rng_arr.size-1]
		total_sentences = lst - frst;
		
		#similar to chapters, build randomly-placed list of phrase ranges, for paragraphs
		paragraph_count = (total_sentences / 8) + 1
		
		para_points = paragraph_count.times.collect {
			rand(total_sentences) + frst;
		}
		para_points << frst;
		para_points << lst;
		para_points = para_points.uniq.sort
		para_ranges = para_points.each_cons(2).collect { |rang| (rang[0]...rang[1]) }
		
		#write paragraph
		pdf.font "Palatino"
		pdf.font_size 12
		para_ranges.each{ |prang|
			pdf.text @db[prang].join(" "), :indent_paragraphs => 60;
		}
	}
	
	#write ending
	pdf.start_new_page
	pdf.font "Times-Roman"
	pdf.formatted_text_box [
		{:text => "THE END", :align => :center, :size => 50}
	], :valign => :center, :align => :center, :height => 400
	
	#last -- do page numbers
	string = "<page>"
	options = {
		:at => [0, 0],
		:align => :center,
		:page_filter => lambda{ |pg| pg > 1},
		:start_count_at => 1,
		:font => "Times-Roman",
		:color => "555555" }
	pdf.number_pages string, options
end