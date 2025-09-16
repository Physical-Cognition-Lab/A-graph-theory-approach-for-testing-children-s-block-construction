
## Parameters

input_folder = 'C:\Users\npeleg\OneDrive - Birkbeck, University of London\Spatial2Dto3D_ET_2024\Datavyu\Coded Files\reviewed'
output_file =  'C:\Users\npeleg\OneDrive - Birkbeck, University of London\Spatial2Dto3D_ET_2024\Datavyu\Coded Files\reviewed\Data\adult_data2.csv'

# This is a listing of all columns and the codes from those columns that should
# be exported.
code_map = {
  'ID'  => %w(id tdate bdate sex),
  'Task' => %w(onset offset model_type correct_final_ci),
  'Construct_Action' => %w(onset offset action_cd target_rgbls verticality_ab orientation_longblock_hv relation1_color_rgbls relation1_orientation_hv relation1_frontback_offset relation1_leftright_offset relation2_color_rgbls relation2_orientation_hv relation2_frontback_offset relation2_leftright_offset relation3_color_rgbls relation3_orientation_hv relation3_frontback_offset relation3_leftright_offset relation4_color_rgbls relation4_orientation_hv relation4_frontback_offset relation4_leftright_offset relation5_color_rgbls relation5_orientation_hv relation5_frontback_offset relation5_leftright_offset relation6_color_rgbls relation6_orientation_hv relation6_frontback_offset relation6_leftright_offset),
  'Perspective_Orienting' => %w(onset offset direction_lr)
}

# Static columns are columns with a single cell. Code values from the first cell
# will be printed.
static_columns = %w[ID]

# Nested columns lists, in order, the hierarchical nesting of columns.
# Cells in the second column will always be nested temporally within cells of
# the first column. Cells in the third column will always be nested temporally
# within cells of the second column. Etc...
# The last column is this list is the innermost nested column.
nested_columns = %w[Task]

# Sequential columns lists columms that should be printed on separate rows.
# If there is at least one nested_column specified, cells from the sequential
# columns will be printed only if they are nested inside the innermost nested cell.
sequential_columns = %w[Construct_Action Perspective_Orienting]

# Linked columns allows printing cells using a custom matching function.
linked_columns = %w[]


delimiter = ','

## Body
require "Datavyu_API.rb"
require "csv"
# all columns to print
all_cols = [static_columns, linked_columns,
            nested_columns, sequential_columns].flatten
# Sanity check parameters.
# Make sure all specified columns have entries in the code map
invalid_cols = all_cols - code_map.keys
unless invalid_cols.empty?
  raise 'Following columns do not have entries in code_map parameter: '\
        "#{invalid_cols.join(', ')}"
end
# Simple method to print nested columns.
# Returns a list of list where the inner list
# is a row of cells corresponding to a line of data to print out.
def nested_print(*columns)
  nested_print_helper(columns, [], [])
end

# Recursive method to add
def nested_print_helper(columns, row_cells, table)
  col = columns.shift

  if col.nil?
    table << row_cells.dup
  else
    cells = col.cells
    oc = row_cells.last
    # select only nested cells if outer cell exists
   # cells = cells.select { |x| oc.contains(x) } unless oc.nil?

    if cells.empty?
      # pad row with nils for missing columns
      # extra nil for the shifted column
      table << (row_cells + [nil] * (columns.size + 1))
    else
      cells.each do |cell|
        row_cells.push(cell)
        nested_print_helper(columns, row_cells, table)
        row_cells.pop
      end
    end
  end
  col && columns.unshift(col)
  table
end

# Function to get a table of sequential cells
# in a diagonal layout: each row has a single
# cell from a single column.
sequential_printer = lambda do |seq_cols, outer_cell|
  return [[]] if seq_cols.empty?
  table = []
  row = Array.new(seq_cols.size)
  seq_cols.each_with_index do |sc, idx|
	if (!sc.nil?)

    seq_cells = sc.cells
    seq_cells = seq_cells.select { |x| outer_cell.contains(x) } unless outer_cell.nil?
    seq_cells.each do |c|
      row[idx] = c
      table << row.dup
    end
    row[idx] = nil
	end
  end
  table
end

# Helper function to get codes from list of cells
# using the column-code mapping.
# Returns a hashmap from column name to list of values
data_map = lambda do |mapping, columns, cells|
  # if no cells, all values are blanks
  cells ||= []
  columns.zip(cells).each_with_object({}) do |(col, cell), h|
    codes = mapping[col]
    h[col] = cell.nil? ? codes.map { '' } : cell.get_codes(codes)
  end
end.curry.call(code_map)

# Flattens out the values of the data map to generate a row of output
data_row = ->(cols, cells) { data_map.call(cols, cells).values.flatten }.curry
all_data = data_row.call(all_cols)

# Header order is: static, bound, nested, sequential
col_header = lambda do |map, col|
  map[col].map { |x| "#{col}_#{x}" }
end.curry.call(code_map)
header = all_cols.flat_map(&col_header)
data = CSV.new(String.new, write_headers: true, headers: header, col_sep: delimiter)

input_path = File.expand_path(input_folder)
infiles = Dir.chdir(input_path) { Dir.glob('*.opf') }
puts infiles.inspect
infiles.sort.each do |infile|
  $db, $pj = load_db(File.join(input_path, infile))
  puts "Printing #{infile}..."
  puts code_map.keys.inspect
  columns = code_map.keys.each_with_object({}) { |x, h| h[x] = get_column(x) }
  columns = code_map.keys.each_with_object({}) do |x, h|
    puts "Processing key: #{x.inspect}"
    h[x] = send(:get_column, x) unless x.nil?
  end


  # Get cells from static columns
  static_cells = static_columns.map do |col|
    columns[col].cells.first
  end

  # map column names to actual columns

  cols = ->(xs) { xs.map { |x| columns[x] } }
  nest_cols = cols.call(nested_columns)
  seq_cols = cols.call(sequential_columns)
  # Get rows of cells for nested columns
  nested_table = nested_print(*nest_cols)
  # Iterate over the cell rows
  nested_table.each do |nested_cells|
    # The innermost cell is in the column at the end of the nested columns list
    innermost_cell = nested_cells.last


    seq_table = sequential_printer.call(seq_cols, innermost_cell)
    # if the table is empty, add a blank row so we can still print
    seq_table << [] if seq_table.empty?

    seq_table.each do |sequential_cells|
      # Get data from bound/linked columns
      linked_cells = linked_columns.each_with_object([]) do |lcol, arr|
        rule = links[lcol]
        lcell = rule.call(
          (static_cells + arr + nested_cells + sequential_cells).compact,
          columns[lcol].cells
        )

        arr << lcell
      end

      all_cells = static_cells + linked_cells + nested_cells + sequential_cells
      row = all_data.call(all_cells)
      data << row
    end
  end
end

puts 'Writing data to file...'
outfile = File.open(File.expand_path(output_file), 'w+')
outfile.puts data.string
outfile.close

puts 'Finished.'
