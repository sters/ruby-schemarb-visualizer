# frozen_string_literal: true

require 'Ripper'
require 'pp'

def indent(n)
    " " * (4 * n)
end

class Visualizer
    def initialize(path)
        @path = path
        @parser = Parser.new(File.read(@path))
        @tables = {}
    end

    def parse
        return if @tables != {}
        @tables = @parser.parse
    end

    def simple
        parse

        result = []
        result << "graph TD"
        @tables.each do |table_name, table|
            if table[:foreign_tables].nil?
                result << "#{indent(1)}#{table_name}"
            else
                table[:foreign_tables].each do |t|
                    result << "#{indent(1)}#{table_name} --> #{t}"
                end
            end
        end

        result.join("\n")
    end
end

class Parser
    def initialize(raw)
        @raw = raw
        @sexp = Ripper.sexp(@raw)
        @tables = {}
    end

    def parse
        # :program
        program = @sexp[1]

        # ActiveRecord::Schema.define
        # program[0][0] == :method_add_block
        # program[0][1][0] == :method_ad_arg
        # pp program[0][1][1][0] == :call
        # pp program[0][1][1][1][0] == :aref
        # pp program[0][1][1][1][1][0] == :const_path_ref
        # pp program[0][1][1][1][1][1][0] == :var_ref
        # pp program[0][1][1][1][1][1][1][0] == :@const
        # pp program[0][1][1][1][1][1][1][1] == "ActiveRecord"
        # pp program[0][1][1][1][1][2][0] == :@const
        # pp program[0][1][1][1][1][2][1] == "Schema"
        # pp program[0][1][2] # version related
        # pp program[0][2][0] == :do_block

        schema_block = program[0][2][2][1]
        schema_block.each do |schema_item|
            # e.g. enable_extension
            if schema_item[0] == :command
                handle_command(schema_item)
                next
            end

            # find create_table do
            next if schema_item[0] != :method_add_block && schema_item[1][0] == :command

            # pp schema_item[1][1][0] == :@ident
            case schema_item[1][1][1]
            when "create_table" then
                t = handle_table(schema_item)
                @tables[t[:name].to_sym] = t
            end
        end

        @tables
    end

    def handle_command(command_info)
        case command_info[1][1]
        when "add_foreign_key"
            from_table = command_info[2][1][0][1][1][1]
            to_table  = command_info[2][1][1][1][1][1]

            @tables[from_table.to_sym][:foreign_tables] ||= []
            @tables[from_table.to_sym][:foreign_tables] << to_table.to_sym
        end
    end

    def handle_table(schema_item)
        table_info = schema_item[1][2][1]
        table_name = table_info[0][1][1][1]

        table_comment = ""
        table_info[1][1].each do |c|
            table_comment = c[2][1][1][1] if c[1][1] == "comment:"
        end

        columns = []

        table_block = schema_item[2][2][1]
        table_block.each do |c|
            column = {}
            column[:type] = c[3][1]

            if column[:type] == "index"
                columns << handle_table_index(column, c)
                next
            end

            columns << handle_table_column(column, c)
        end

        return {
            name: table_name,
            comment: table_comment,
            columns: columns,
        }
    end

    def handle_table_column(column, c)
        column_info = c[4][1]
        column[:name] = column_info[0][1][1][1]

        if !column_info[1].nil? && column_info[1][0] == :bare_assoc_hash
            column_info[1][1].each do |cc|
                x = ""
                unless cc[2][1][1].nil?
                    x = cc[2][1][1][1] if cc[2][0] == :string_literal
                    x = cc[2][1][1] if cc[2][0] == :var_ref
                end
                column[cc[1][1].sub(':', '').to_sym] = x
            end
        end

        column
    end

    def handle_table_index(column, c)
        column_info = c[4][1]

        column[:keys] = []
        column_info[0][1].each do |cc|
            column[:keys] << cc[1][1][1]
        end

        column_info[1][1].each do |cc|
            x = ""
            unless cc[2][1][1].nil?
                x = cc[2][1][1][1] if cc[2][0] == :string_literal
                x = cc[2][1][1] if cc[2][0] == :var_ref
            end
            column[cc[1][1].sub(':', '').to_sym] = x
        end

        column
    end
end

