require "bundler"
Bundler.require
require "pathname"
require "yaml"
require "date"

class ImageName
	attr_reader :instance_name
	attr_reader :time
	def initialize(instance_name, time)
		@instance_name = instance_name
		@time = time
	end
	def to_s
		time_str = time.strftime("%Y-%m-%d_%H-%M-%S")
		ss = [
			"name=#{instance_name}",
			"time=#{time_str}"
		]
		return "(#{ss.join(", ")})"
	end
	def inspect
		to_s
	end
	def self.parse(string)
		regex = /(\S*)_([\d]+)-([\d]+)-([\d]+)_([\d]+)-([\d]+)-([\d]+)/
		m = regex.match(string)
		if ! m
			return nil
		end
		i = 1
		instance_name = m[i]
		i += 1

		time = DateTime.new(m[i+0].to_i, m[i+1].to_i, m[i+2].to_i, 
			m[i+3].to_i, m[i+4].to_i, m[i+5].to_i, DateTime.now.offset)

		return ImageName.new(instance_name, time)
	end
end

class App
	def print_usage
		puts "usage: #{$PROGRAM_NAME}"
	end
	def get_instance_name(instance)
		instance.tags.select {|x| x.key == "Name" }.map {|x| x.value }.first
	end
	def parse_image_name(image_name)
		image_name
	end
	attr_reader :ec2
	attr_reader :config
	def main
		config_path = Pathname.new(__FILE__).parent.parent + "config/config.yml"
		@config = YAML.load(config_path.read())

		@ec2 = Aws::EC2::Client.new(
			region: config["region"],
			credentials: Aws::Credentials.new(
			config["access_key_id"], config["secret_access_key"])
			)

		for instance_id in config["target_instance_ids"]
			backup_instance(instance_id)
		end
	end
	def backup_instance(instance_id)
		now = DateTime.now
		max_age = config["backup_max_age_in_days"].to_f * 86400

		instances_ret = ec2.describe_instances(instance_ids: [instance_id])
		target_instance = instances_ret.reservations.first.instances.first

		target_instance_name = get_instance_name(target_instance)

		image_name = target_instance_name + "_" + now.strftime("%Y-%m-%d_%H-%M-%S")

		ec2.create_image(
			instance_id: instance_id,
			name: image_name)

		# インスタンスのイメージを古い順でソートして、
		# 一定以上古いものを破棄する
		images_ret = ec2.describe_images(owners: ["self"])
		images = images_ret.images
			.map {|x| [ ImageName.parse(x.name), x ]  }
			.select {|x| x[0] && x[0].instance_name == target_instance_name }
			.sort {|x, y| -1 * (x[0].time <=> y[0].time) }
		del_images = images.select {|x| (now - x[0].time) * 86400 > max_age }
		for del_image in del_images
			ec2.deregister_image(image_id: del_image[1].image_id)
			for block_device_mapping in del_image[1].block_device_mappings
				snapshot_id = block_device_mapping.ebs.snapshot_id
				ec2.delete_snapshot(snapshot_id: snapshot_id)
			end
		end
	end
end

app = App.new
app.main

