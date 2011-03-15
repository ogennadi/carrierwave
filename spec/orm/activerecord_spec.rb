# encoding: utf-8

require 'spec_helper'

require 'carrierwave/orm/activerecord'

# change this if sqlite is unavailable
dbconfig = {
  :adapter => 'sqlite3',
  :database => ':memory:'
}

ActiveRecord::Base.establish_connection(dbconfig)
ActiveRecord::Migration.verbose = false

class TestMigration < ActiveRecord::Migration
  def self.up
    create_table :events, :force => true do |t|
      t.column :name, :string
      t.column :image, :string
      t.column :textfile, :string
      t.column :foo, :string
    end
  end

  def self.down
    drop_table :events
  end
end

class Event < ActiveRecord::Base; end # setup a basic AR class for testing
$arclass = 0

describe CarrierWave::ActiveRecord do

  describe '.mount_uploader' do

    before(:all) { TestMigration.up }
    after(:all) { TestMigration.down }
    after { Event.delete_all }

    before do
      # My god, what a horrible, horrible solution, but AR validations don't work
      # unless the class has a name. This is the best I could come up with :S
      $arclass += 1
      @class = Class.new(Event)
      # AR validations don't work unless the class has a name, and
      # anonymous classes can be named by assigning them to a constant
      Object.const_set("Event#{$arclass}", @class)
      @class.table_name = "events"
      @uploader = Class.new(CarrierWave::Uploader::Base)
      @class.mount_uploader(:image, @uploader)
      @event = @class.new
    end

    describe '#image' do

      it "should return blank uploader when nothing has been assigned" do
        @event.image.should be_blank
      end

      it "should return blank uploader when an empty string has been assigned" do
        @event[:image] = ''
        @event.save
        @event.reload
        @event.image.should be_blank
      end

      it "should retrieve a file from the storage if a value is stored in the database" do
        @event[:image] = 'test.jpeg'
        @event.save
        @event.reload
        @event.image.should be_an_instance_of(@uploader)
      end

      it "should set the path to the store dir" do
        @event[:image] = 'test.jpeg'
        @event.save
        @event.reload
        @event.image.current_path.should == public_path('uploads/test.jpeg')
      end

    end

    describe '#image=' do

      it "should cache a file" do
        @event.image = stub_file('test.jpeg')
        @event.image.should be_an_instance_of(@uploader)
      end

      it "should write nothing to the database, to prevent overriden filenames to fail because of unassigned attributes" do
        @event[:image].should be_nil
      end

      it "should copy a file into into the cache directory" do
        @event.image = stub_file('test.jpeg')
        @event.image.current_path.should =~ %r(^#{public_path('uploads/tmp')})
      end

      it "should do nothing when nil is assigned" do
        @event.image = nil
        @event.image.should be_blank
      end

      it "should do nothing when an empty string is assigned" do
        @event.image = ''
        @event.image.should be_blank
      end

      context 'when validating integrity' do
        before do
          @uploader.class_eval do
            def extension_white_list
              %w(txt)
            end
          end
          @event.image = stub_file('test.jpg')
        end

        it "should make the record invalid when an integrity error occurs" do
          @event.should_not be_valid
        end

        it "should use I18n for integrity error messages" do
          @event.valid?
          @event.errors[:image].should == ['is not an allowed file type']

          change_locale_and_store_translations(:pt, :activerecord => {
            :errors => {
              :messages => {
                :carrierwave_integrity_error => 'tipo de imagem não permitido.'
              }
            }
          }) do
            @event.should_not be_valid
            @event.errors[:image].should == ['tipo de imagem não permitido.']
          end
        end
      end

      context 'when validating processing' do
        before do
          @uploader.class_eval do
            process :monkey
            def monkey
              raise CarrierWave::ProcessingError, "Ohh noez!"
            end
          end
          @event.image = stub_file('test.jpg')
        end

        it "should make the record invalid when a processing error occurs" do
          @event.should_not be_valid
        end

        it "should use I18n for processing error messages" do
          @event.valid?
          @event.errors[:image].should == ['failed to be processed']

          change_locale_and_store_translations(:pt, :activerecord => {
            :errors => {
              :messages => {
                :carrierwave_processing_error => 'falha ao processar imagem.'
              }
            }
          }) do
            @event.should_not be_valid
            @event.errors[:image].should == ['falha ao processar imagem.']
          end
        end
      end

    end

    describe '#save' do

      it "should do nothing when no file has been assigned" do
        @event.save.should be_true
        @event.image.should be_blank
      end

      it "should copy the file to the upload directory when a file has been assigned" do
        @event.image = stub_file('test.jpeg')
        @event.save.should be_true
        @event.image.should be_an_instance_of(@uploader)
        @event.image.current_path.should == public_path('uploads/test.jpeg')
      end

      it "should do nothing when a validation fails" do
        @class.validate { |r| r.errors.add :textfile, "FAIL!" }
        @event.image = stub_file('test.jpeg')
        @event.save.should be_false
        @event.image.should be_an_instance_of(@uploader)
        @event.image.current_path.should =~ /^#{public_path('uploads/tmp')}/
      end

      it "should assign the filename to the database" do
        @event.image = stub_file('test.jpeg')
        @event.save.should be_true
        @event.reload
        @event[:image].should == 'test.jpeg'
      end

      it "should preserve the image when nothing is assigned" do
        @event.image = stub_file('test.jpeg')
        @event.save.should be_true
        @event = @class.find(@event.id)
        @event.foo = "bar"
        @event.save.should be_true
        @event[:image].should == 'test.jpeg'
      end

      it "should remove the image if remove_image? returns true" do
        @event.image = stub_file('test.jpeg')
        @event.save!
        @event.remove_image = true
        @event.save!
        @event.reload
        @event.image.should be_blank
        @event[:image].should == ''
      end

      it "should mark image as changed when saving a new image" do
        @event.image_changed?.should be_false
        @event.image = stub_file("test.jpeg")
        @event.image_changed?.should be_true
        @event.save
        @event.reload
        @event.image_changed?.should be_false
        @event.image = stub_file("test.jpg")
        @event.image_changed?.should be_true
        @event.changed_for_autosave?.should be_true
      end
    end

    describe '#destroy' do

      it "should do nothing when no file has been assigned" do
        @event.save.should be_true
        @event.destroy
      end

      it "should remove the file from the filesystem" do
        @event.image = stub_file('test.jpeg')
        @event.save.should be_true
        @event.image.should be_an_instance_of(@uploader)
        @event.image.current_path.should == public_path('uploads/test.jpeg')
        @event.destroy
        File.exist?(public_path('uploads/test.jpeg')).should be_false
      end

    end

    describe 'with overridden filename' do

      describe '#save' do

        before do
          @uploader.class_eval do
            def filename
              model.name + File.extname(super)
            end
          end
          @event.name = "jonas"
        end

        it "should copy the file to the upload directory when a file has been assigned" do
          @event.image = stub_file('test.jpeg')
          @event.save.should be_true
          @event.image.should be_an_instance_of(@uploader)
          @event.image.current_path.should == public_path('uploads/jonas.jpeg')
        end

        it "should assign an overridden filename to the database" do
          @event.image = stub_file('test.jpeg')
          @event.save.should be_true
          @event.reload
          @event[:image].should == 'jonas.jpeg'
        end

      end

    end

    describe 'with validates_presence_of' do

      before do
        @class.validates_presence_of :image
        @event.name = "jonas"
      end

      it "should be valid if a file has been cached" do
        @event.image = stub_file('test.jpeg')
        @event.should be_valid
      end

      it "should not be valid if a file has not been cached" do
        @event.should_not be_valid
      end

    end

    describe 'with validates_size_of' do

      before do
        @class.validates_size_of :image, :maximum => 40
        @event.name = "jonas"
      end

      it "should be valid if a file has been cached that matches the size criteria" do
        @event.image = stub_file('test.jpeg')
        @event.should be_valid
      end

      it "should not be valid if a file has been cached that does not match the size criteria" do
        @event.image = stub_file('bork.txt')
        @event.should_not be_valid
      end

    end

    describe 'removing previously stored files' do
      after do
        FileUtils.rm_rf(file_path("uploads"))
      end

      it "should work with fog" do
        pending # TODO note - we should check that this works with fog, maybe in the fog spec
      end

      it "should work with mongoid" do
        pending # TODO note - we should get this working with mongoid, maybe in the mongoid spec
      end

      it "should work with mongoid" do
        pending # TODO note - we should test that this all works with multiple mounted uploaders
      end

      describe 'without additional options' do
        before do
          @event.image = stub_file('test.jpeg')
          @event.save.should be_true
          File.exists?(public_path('uploads/test.jpeg')).should be_true
        end

        it "should remove previous image if previous image had a different path" do
          @event.image = stub_file('test.jpg')
          @event.save.should be_true
          File.exists?(public_path('uploads/test.jpg')).should be_true
          File.exists?(public_path('uploads/test.jpeg')).should be_false
        end

        it "should not remove previous image if previous image had a different path but remove_previous_files is false" do
          pending
          # we should have an option to retain the old behavior,
          # just in case someone wants to be safe, because really we could be
          # deleting files that some other part of the system wants without us knowing.
          # i'm not sure if remove_previous_files should default to true or not... something like:
          # @event.stub!(:remove_previous_files).and_return(false)
          @event.image = stub_file('test.jpg')
          @event.save.should be_true
          File.exists?(public_path('uploads/test.jpg')).should be_true
          File.exists?(public_path('uploads/test.jpeg')).should be_false
        end

        it "should not remove image if previous image had the same path" do
          @event.image = stub_file('test.jpeg')
          @event.save.should be_true
          File.exists?(public_path('uploads/test.jpeg')).should be_true
        end

        it "should not remove image if validations fail on save" do
          @class.validate { |r| r.errors.add :textfile, "FAIL!" }
          @event.image = stub_file('landscape.jpg')
          @event.save.should be_false
          File.exists?(public_path('uploads/test.jpg')).should be_true
          File.exists?(public_path('uploads/landscape.jpg')).should be_false
        end
      end

      describe 'with mount_on' do
        before do
          # jnicklas: One tiny nit pick would be that this seems to ignore the :mount_on option
          # which can be set for mount_uploader, though I'm not sure if anyone actually uses that.
          # Still might be worth investigating.

          pending # mount_on => :monkey
        end

        it "should remove previous image with mount_on value if previous image had a different path" do
          pending
        end

        it "should not remove previous image with mount_on value if previous image had the same path" do
          pending
        end
      end

      describe 'with versions' do
        before do
          pending # version :thumb
        end

        it "should remove previous image versions if previous image had a different path" do
          pending
        end

        it "should not remove previous image versions if previous image had the same path" do
          pending
        end
      end

      describe 'with an overriden filename' do
        before do
          @uploader.class_eval do
            def filename
              model.name + File.extname(super)
            end
          end

          @event.name = "jonas"

          @event.image = stub_file('test.jpg')
          @event.save.should be_true
          File.exists?(public_path('uploads/jonas.jpg')).should be_true
          @event.image.read.should == "this is stuff"
        end

        it "should not remove image if previous image had the same dynamic path" do
          @event.image = stub_file('landscape.jpg')
          @event.save.should be_true
          File.exists?(public_path('uploads/jonas.jpg')).should be_true
          @event.image.read.should_not == "this is stuff"
        end

        it "should remove previous image if previous image had a different dynamic path" do
          # bundle exec spec spec/orm/activerecord_spec.rb:431
          # see mount.rb for notes
          @event.name = "jose"
          @event.image = stub_file('landscape.jpg')
          @event.save.should be_true
          File.exists?(public_path('uploads/jose.jpg')).should be_true
          File.exists?(public_path('uploads/jonas.jpg')).should be_false
          @event.image.read.should_not == "this is stuff"
        end
      end
    end

  end

end
