class DropboxImporter
  FAILED_DIR_FILE_PATH = '/failed'

  attr_reader :bulk_upload

  def initialize(dh2o)
    @dh2o = dh2o
  end

  def paths_to_import
    @dh2o.file_paths - paths_already_imported
  end

  def paths_of_dupes
    @paths_already_imported ||= (@dh2o.file_paths - self.paths_to_import)
  end

  def import(klass, bulk_upload)
    @klass = klass
    @bulk_upload = bulk_upload
    paths_to_import.each do |path|
      import!(path)
    end
    handle_dupes
    self.bulk_upload
  end

  def import!(path)
    new_instance = build_instance(path)
    if new_instance.save
      handle_import_success(path, new_instance)
    else
      handle_import_error(path, new_instance)
    end
  end

  def build_instance(path)
    file_contents = @dh2o.get_file(path)
    new_instance = @klass.new_from_xml_file(file_contents)
    new_instance
  end

  def handle_import_success(path, new_instance)
    puts "saved file woot!"
    record_import(:bulk_upload => self.bulk_upload,
                  :actual_object => new_instance,
                  :dropbox_filepath => path,
                  :status => 'Object Created')
  end

  def handle_import_error(path, new_instance)
    puts "file didn't save"
    self.bulk_upload.update_attribute('has_errors', true)
    @dh2o.copy_to_failed_dir(path)
    @dh2o.write_error(path, new_instance.errors.full_messages.join(", "))
    record_import(:bulk_upload => self.bulk_upload,
                  :dropbox_filepath => path,
                  :status => 'Errored')
  end

  def handle_dupes
    self.paths_of_dupes.each do |path|
      puts "Dupe recorded"
      record_import(:bulk_upload => self.bulk_upload,
                    :dropbox_filepath => path,
                    :status => 'Dupe Detected')
    end

  end

  def copy_to_failed_dir(path)
    @dh2o.copy_to_dir(FAILED_DIR_FILE_PATH, path)
  end

  def import_file_paths
    res = @dh2o.file_paths
    res = res - excluded_file_paths
    res
  end

  def excluded_file_paths
    [FAILED_DIR_FILE_PATH, DropboxErrorLog::ERROR_LOG_PATH]
  end

  def record_import(options = {})
    Import.create!(options)
  end

  def paths_already_imported
    @paths_already_imported ||= Import.completed_paths(@klass)
    puts @klass.inspect
    @paths_already_imported
  end
end