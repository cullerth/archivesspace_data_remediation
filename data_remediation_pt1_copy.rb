require 'bundler/setup'
Bundler.require
require './as_config_production.rb'
require 'csv'

# read in search terms to pass
@search_terms = IO.readlines("search_terms.txt").each { |line| line.gsub!( "\n", '' ) }
# initialize connection
@a = ArchivesSpaceApiUtility::ArchivesSpaceSession.new
# set page size for paginated search requests
@page_size = 10
# define CSV headers - we'll use this 2 different ways
@csv_headers = ['uri', 'title', 'notes']


# Use this method to perform the API request to search the notes field on a record for whatever term
def get_terms(page=1, term)
  # set API endpoint
  path = '/search'
  # build query parameters
  params = {}
  params[:page] = page
  params[:page_size] = @page_size
  params[:q] = "notes:#{term}"
  # execute request
  response = @a.get(path, params)
  # convert JSON to Hash
  JSON.parse(response.body)
end

# process raw values from API response (a hash) to array of values for a row in the CSV
# creates resolvable links to individual records on archivesspace
# removes line breaks from strings and replaces them with ' | '
def values_to_row(hash)
  @csv_headers.map do |h|
    if hash[h].include? 'resources'
      hash[h].gsub!( /\/repositories\/\d\//, 'https://staff.archivesspace.lib.ncsu.edu/' )
    elsif hash[h].include? 'archival_objects'
      hash[h].gsub!( /\/repositories\/\d\/archival_objects\//, 'https://staff.archivesspace.lib.ncsu.edu/resolve/readonly?uri=\0' )
    elsif hash[h].include? 'digital_objects'
      hash[h].gsub!( /\/repositories\/\d\//, 'https://staff.archivesspace.lib.ncsu.edu/' )
    elsif hash[h].include? 'agents'
      hash[h].gsub!( /\/agents\/people\//, 'https://staff.archivesspace.lib.ncsu.edu/resolve/readonly?uri=/agents/people/\0' )
    else
      hash[h]
    end
    if hash[h].is_a? String
      hash[h].strip.gsub(/[\n\r]+/, ' | ')
    else
      hash[h]
    end
  end
end

def get_rows(term)
  rows = []
  # do an initial query to get the total results, and use that to determine number of pages
  data = get_terms(term)
  count = data['total_hits']
  pages = (count.to_f / @page_size).ceil

  # set page to begin iterating through all pages of results
  page = 1

  puts "Fetching #{count} records for '#{term}'..."
  # do a request for each page and put each record in @rows
  while (page <= pages) do
    data = get_terms(page, term)
    results = data['results']
    results.each do |r|
      # This is the easy version that doesn't replace line breaks
      # rows << @csv_headers.map { |h| r[h] }

      # This is the better version
      rows << values_to_row(r)
    end
    page += 1
    print '.' # to provide a little visual feedback while the script runs
  end
  puts # just to add a line break to the terminal output
  rows
end

def generate_csv(rows, term)
  # create a new directory for CSV files if it doesn't exist
  csv_dir = './csv'
  Dir.mkdir(csv_dir) if !Dir.exist?(csv_dir)

  # set file name for CSV to be generated
  csv_filepath = "#{csv_dir}/#{term}.csv"

  # use CSV.open to create a writable .csv file and write to it
  CSV.open(csv_filepath, 'w', headers: @csv_headers, write_headers: true, force_quotes: true) do |csv|
    rows.each do |row|
      csv << row
    end
  end
end

#put it all together! iterate through each term in the text file 
@search_terms.each do |word|
  rows = get_rows(term=word)
  generate_csv(rows, term=word)
end
