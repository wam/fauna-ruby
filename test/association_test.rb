require File.expand_path('../test_helper', __FILE__)

class AssociationTest < MiniTest::Unit::TestCase

  def setup
    super

    @pig = Pig.create!(:name => "Henwen")
    @vision = Vision.create!(:pronouncement => "It was a dark and stormy night...", :pig => @pig)
    @pig.visions.add @vision
  end

  def test_event_set
    assert_equal @pig.visions.page.events.first.resource, @vision
    assert @pig.visions.page.events.first.resource.pronouncement
  end

  def test_reference
    assert_equal @vision.pig, @pig
    assert_equal @vision.pig_ref, @pig.ref
    assert @vision.pig.visions
  end
end
