require 'digest/md5'
require_relative '../lib/commands'

describe Metis::Assimilate do
  before(:each) do
    default_bucket('athena')
    @cmd = Metis::Assimilate.new
  end

  after(:each) do
    stubs.clear

    expect(stubs.contents(:athena)).to be_empty
  end

  it 'moves files and folders into the root folder path' do
    stubs.create_data('stubs', 'wisdom.txt', WISDOM)
    stubs.create_data('stubs', 'blueprints/helmet.txt', HELMET)

    @cmd.execute('athena', 'files', '/', 'spec/stubs/wisdom.txt', 'spec/stubs/blueprints')

    expect(Metis::File.count).to eq(2)
    expect(Metis::Folder.count).to eq(1)

    wisdom_file, helmet_file = Metis::File.all
    blueprints_folder = Metis::Folder.first

    # the file records are there, nested appropriately, with real data
    expect(wisdom_file.file_name).to eq('wisdom.txt')
    expect(wisdom_file.folder).to be_nil
    expect(wisdom_file).to be_has_data
    expect(File.read(wisdom_file.location)).to eq(WISDOM)

    expect(helmet_file.file_name).to eq('helmet.txt')
    expect(helmet_file.folder).to eq(blueprints_folder)
    expect(helmet_file).to be_has_data
    expect(File.read(helmet_file.location)).to eq(HELMET)

    # folders are also created
    expect(blueprints_folder.folder_name).to eq('blueprints')
    expect(blueprints_folder).to be_root_folder
    expect(blueprints_folder).to be_has_directory

    # the original files are untouched
    expect(::File.exists?('spec/stubs/wisdom.txt')).to be_truthy
    expect(::File.exists?('spec/stubs/blueprints/helmet.txt')).to be_truthy
    File.delete(wisdom_file.location)
    File.delete(helmet_file.location)
    Dir.delete(blueprints_folder.location)
  end

  it 'moves files and folders into a folder path' do
    upload_folder = create_folder('athena', 'upload')
    stubs.create_folder('athena', 'upload')

    stubs.create_data('stubs', 'wisdom.txt', WISDOM)
    stubs.create_data('stubs', 'blueprints/helmet.txt', HELMET)

    @cmd.execute('athena', 'files', '/upload', 'spec/stubs/wisdom.txt', 'spec/stubs/blueprints')

    expect(Metis::File.count).to eq(2)
    expect(Metis::Folder.count).to eq(2)

    upload_folder, blueprints_folder = Metis::Folder.all
    wisdom_file, helmet_file = Metis::File.all

    expect(wisdom_file.folder).to eq(upload_folder)
    expect(helmet_file.folder).to eq(blueprints_folder)
    expect([wisdom_file, helmet_file]).to all(be_has_data)

    File.delete(wisdom_file.location)
    File.delete(helmet_file.location)
    Dir.delete(blueprints_folder.location)
  end

  it 'refuses to overwrite existing folders' do
    blueprints_folder = create_folder('athena', 'blueprints')
    stubs.create_folder('athena', 'blueprints')

    stubs.create_data('stubs', 'blueprints/helmet.txt', HELMET)

    expect {
      @cmd.execute('athena', 'files', '/', 'spec/stubs/blueprints')
    }.to raise_error(ArgumentError)

    expect(Metis::File.count).to eq(0)
    expect(Metis::Folder.count).to eq(1)
  end

  it 'refuses to overwrite existing files' do
    blueprints_folder = create_folder('athena', 'blueprints')
    stubs.create_folder('athena', 'blueprints')

    helmet_file = create_file('athena', 'helmet.txt', HELMET, folder: blueprints_folder)
    stubs.create_file('athena', 'blueprints/helmet.txt', HELMET)

    stubs.create_data('stubs', 'helmet.txt', HELMET)

    expect {
      @cmd.execute('athena', 'files', '/blueprints', 'spec/stubs/helmet.txt')
    }.to raise_error(ArgumentError)

    expect(Metis::File.count).to eq(1)
    expect(Metis::Folder.count).to eq(1)
  end
end
