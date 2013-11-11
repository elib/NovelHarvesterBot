require 'rubygems'

#require RC version of twitter for streaming
gem "twitter", "~> 5.0.0.rc.1"
require 'twitter'
require 'time'
require 'json'
require 'yaml'

#boilerplate for logging
def log text
  @logfile.write( "\r\n" + Time.new.to_s + ": " + text.to_s())
  puts text;
end
@logfile = File.new('thewaybot_log.txt', "a")

#initialize databases and filenames
@db = []
@db_file = "db.dat"

@used_phrases = {}
@used_handles = {}

@phrase_file_name = "phrases.dat";
@handle_file_name = "handles.dat";

#a semi-generic way to load collections (hash or array) using JSON
def load_collection_from_file(filename, default)

	return default unless File.exists?(filename)
	
	file = File.new(filename, 'r');
	file_json = file.read;
	file.close;
	collection = JSON.load(file_json);
	
	log("Loaded #{collection.length} collection item(s) from #{filename}.");
	
	return collection;
end

#a semi-generic way to save collections (using JSON)
def save_collection_to_file(filename, collection)
	collection_str = JSON.pretty_generate(collection)
	outfile = File.new(filename, "w");
	outfile.write(collection_str)
	outfile.close;
end

#these ended up rather silly one-line methods to load and save stuff.
def load_used_phrases
	@used_phrases = load_collection_from_file(@phrase_file_name, {});
end

def load_used_handles
	@used_handles = load_collection_from_file(@handle_file_name, {});
end

def load_db
	@db = load_collection_from_file(@db_file, []);
end

def save_used_handles
	save_collection_to_file(@handle_file_name, @used_handles);
end

#load configuration from config.yml -- you must provide this file yourself
twitter_config = YAML.load_file('config.yml')

#first twitter client -- streaming (for collecting tweets)
client = Twitter::Streaming::Client.new do |config|
  config.consumer_key = twitter_config["consumer_key"]
  config.consumer_secret = twitter_config["consumer_secret"]
  config.oauth_token = twitter_config["oauth_token"]
  config.oauth_token_secret = twitter_config["oauth_token_secret"]
end

#second twitter client -- REST (for writing tweets)
write_client = Twitter::REST::Client.new do |config|
  config.consumer_key = twitter_config["consumer_key"]
  config.consumer_secret = twitter_config["consumer_secret"]
  config.oauth_token = twitter_config["oauth_token"]
  config.oauth_token_secret = twitter_config["oauth_token_secret"]
end

#main method for running the collection engine
def start_tracking(phrase_text, used_phrase_list, used_phrase_filename, client, write_client, number_of_phrases, exclude_phrase_test = nil)
	#build phrase regex
	phrase_test = Regexp.new(phrase_text + "([^\\.\\?\\!#\\@](?<!http|$))+(\\.|\\!|\\Z)", Regexp::IGNORECASE | Regexp::MULTILINE);
	puts(phrase_test.inspect)
	
	#Stolen from stack overflow, quick and simple way to remove all ambiguous unicode chars.
	encoding_options = {
		:invalid           => :replace,  # Replace invalid byte sequences
		:undef             => :replace,  # Replace anything not defined in ASCII
		:replace           => '',        # Use a blank for those replacements
		:universal_newline => true       # Always break lines with \n
	}
	
	#not sure the < and > ones are necessary. But the &amp; -> & certainly was. Is this a JSON thing?
	to_replace = [
			["&amp;", "&"],
			["&lt;", "<"],
			["&gt;", ">"]
		]
	
	#limit tweeting to once every 90 seconds. This is just under the 1000 tweets/day rule.
	timeout = 90 * number_of_phrases;
	#report on novel material collection every 10 minutes.
	timeout_count_words = 60 * 10;
	next_tweet = Time.now;
	next_count = Time.now;
	
	#start listening to the basic phrase query
	client.filter(:track => phrase_text) do |tweet|
		
		#exclude if we have been provided with an exclusion test
		next if (!exclude_phrase_test.nil? and tweet.text =~ exclude_phrase_test)
		
		#apply fancy regex
		sub = tweet.text[phrase_test];
		if(!sub.nil?) then
			
			#remove unicode as defined above
			sub = sub.encode Encoding.find('ASCII'), encoding_options
			
			#replace special entities as defined above
			to_replace.each { |rep| 
				sub.gsub!(rep[0], rep[1]);
			}
			
			#separately, save a compact version of this phrase for testing against already-seen list
				phrase = sub.clone;
				#remove all punctuation
				phrase.gsub!(/[[:punct:]]/, "");
				#remove all whitespace
				phrase.gsub!(/\s/, "");
				#force all to lowercase
				phrase.downcase!
			
			#check against already-seen database
			if(used_phrase_list[phrase].nil? and @used_handles[tweet.user.handle].nil?) then
				#register as seen
				used_phrase_list[phrase] = 1;
				@used_handles[tweet.user.handle] = 1;
				
				#add some punctuation bells and whistles to make prettier:
					#add period if no ending punctuation
					sub << "." if sub !~ /[[:punct:]]$/
					#begin with a capital
					sub[0] = sub[0].upcase;
					#remove whitespace before the final punctuation
					sub.gsub!(/\s*([[:punct:]]+$)/, '\1');
				
				#Save this pretty phrase to the novel phrase list
				log("Saving to database: #{sub}");
				@db << sub;
				
				#save all changed databases
				save_collection_to_file(@db_file, @db);
				save_collection_to_file(used_phrase_filename, used_phrase_list);
				save_used_handles
				
				#check if we can tweet this phrase
				if Time.now >= next_tweet then
					#tweet it
					log("Tweeting: #{sub}");
					write_client.update(sub);
					next_tweet = Time.now + timeout;
				end
				
				#check if we should report on novel completion
				if Time.now >= next_count then
					count = @db.inject(0) { |n, item| item.split(" ").length + n}
					target = 51000;
					percent = 100 * count / target.to_f;
					pretty_count = count.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse;
					log("\t***** Total word count is currently: #{pretty_count} (#{percent}% of the way!) *****");
					
					next_count = Time.now + timeout_count_words;
				end
			end
		end
	end
end

# ** STARTUP ** #

#load databases from file
load_used_phrases
load_used_handles
load_db

log("starting!")

#holdover from failed multithreading trials
phrase_count = 1;

#start the engine with "the way that", our seed phrase
start_tracking("the way that", @used_phrases, @phrase_file_name, client, write_client, phrase_count, /by\s*the way that/i)

#this never happens because start_tracking blocks forever
@logfile.close