describe Fastlane::Actions::S3Action do
  describe '#run' do
    it 'prints a message' do
      expect(Fastlane::UI).to receive(:message).with("The s3 plugin is working!")

      Fastlane::Actions::S3Action.run(nil)
    end
  end
end
