require 'geohash_native'
require 'geo_ruby'
require 'georuby-extras'
#require 'geo_ruby_extensions'

module GeoRuby
  module SimpleFeatures
    class GeoHash < Envelope
  
      extend GeoHashNative
      attr_reader :value, :point

      BASE32="0123456789bcdefghjkmnpqrstuvwxyz"
  
      # Create new geohash from a Point, String, or Array of Latlon
      def initialize(*params)
        if (params.first.is_a?(Point))
          point, precision = params
          @value = GeoHash.encode_base(point.x, point.y, precision || 10)
          @point = point
        elsif (params.first.is_a?(String))
          @value = params.first
        elsif (params.size>=2 && params[0].is_a?(Float) && params[1].is_a?(Float))
          precision = params[2] || 10
          @value = GeoHash.encode_base(params[0], params[1], precision)
          @point = Point.from_lon_lat(params[0], params[1])
        end
        points = GeoHash.decode_bbox(@value)
        @lower_corner, @upper_corner =  points.collect{|point_coords| Point.from_coordinates(point_coords,srid,with_z)}
        @point ||= center
      end
  
      def to_s
        @value
      end
    
      def contains?(point)
        ((@lower_corner.x..@upper_corner.x) === point.x) &&
        ((@lower_corner.y..@upper_corner.y) === point.y)
      end

      def neighbor(dir)
        GeoHash.new(GeoHash.calculate_adjacent(@value, dir))
      end
  
      # Returns the immediate neighbors of a given hash value,
      # to the same level of precision as the source
      def neighbors(options = {})
        return @neighbors if @neighbors
        right_left = [0,1].map { |d| GeoHash.calculate_adjacent(@value, d) }
        top_bottom = [2,3].map { |d| GeoHash.calculate_adjacent(@value, d) }
        diagonals = right_left.map { |v| [2,3].map { |d| GeoHash.calculate_adjacent(v, d) } }.flatten
        @neighbors = right_left + top_bottom + diagonals
        options[:value_only] ? @neighbors : @neighbors.map { |v| GeoHash.new(v) }
      end
      
      def extend_to(geohash, dir)
        list = [self]
        current = self
        begin
          new_neighbor = GeoHash.new(GeoHash.calculate_adjacent(current.value, dir))
          list << new_neighbor
          current = new_neighbor
        end until current.value == geohash.value
        list
      end
      
      def decimal_value
        l = @value.size
        num = 0
        0.upto(l) do |d|
          c = @value[l-d-1]
          digit = BASE32.index(c)
          decval = digit * (32**d)
          #puts "#{@value} (#{c}) = #{digit} (#{decval} : 32^#{d})"
          num += decval
        end
        num
      end

      def neighbors_in_range(radius)
        cells = [45,135,225,315].map { |b| GeoHash.new(self.point.point_at_bearing_and_distance(b,radius), value.size) }
        cells << self
        top_row = cells[3].extend_to(cells[0], 0)
        rows = top_row
        current_row = top_row
        begin
          row = current_row.map { |c| GeoHash.new(GeoHash.calculate_adjacent(c.value, 3)) }
          rows.concat(row)
          current_row = row
        end until current_row.first.value == cells[2].value
        rows.concat [265,270,90,95,85,80,100].map { |b| GeoHash.new(self.point.point_at_bearing_and_distance(b,radius), value.size) }
      end
  
      def four_corners
        upper_corner_2 = Point.from_lon_lat(@lower_corner.lon, @upper_corner.lat)
        lower_corner_2 = Point.from_lon_lat(@upper_corner.lon, @lower_corner.lat)
        [@upper_corner, upper_corner_2, @lower_corner, lower_corner_2]
      end
  
      def children
        BASE32.scan(/./).map { |digit| GeoHash.new("#{self.value}#{digit}") }
      end

      def children_within_radius(r, from_point=self.center)
        return [self] if hash_within_radius?(self, r, from_point)
        list = []
        children.each do |child|
          if hash_within_radius?(child, r, from_point)
            list << child
          elsif @value.size < 6
            list.concat child.children_within_radius(r, from_point)
          end
        end
        list
      end
  
      def largest_parent_within_radius(r)
        last_parent = nil
        (3..(@value.size-1)).to_a.find { |precision| last_parent = GeoHash.new(self.point,precision); hash_within_radius?(last_parent, r) }
        last_parent
      end
      
      def hash_within_radius?(gh, r, from_point=self.point)
        return false if gh.four_corners.find { |p| from_point.ellipsoidal_distance(p) > r }
        true
      end
            
      def neighbors_within_radius(r)
        #largest_parent_within_radius(r).neighbors_in_range(r)
        largest_parent_within_radius(r).neighbors_in_range(r).map { |parent| parent.children_within_radius(r, self.point) }.flatten
      end
      
    end
  end
end
