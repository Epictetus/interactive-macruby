require File.expand_path("../spec_helper", __FILE__)

describe "ObjectNode" do
  it "is a subclass of ExpandableNode" do
    ObjectNode.superclass.should == ExpandableNode
  end

  it "returns an instance of the appropriate ObjectNode subclass for a given object" do
    ObjectNode.nodeForObject(Object.new).class.should == ObjectNode
    ObjectNode.nodeForObject(String).class.should == ModNode
    ObjectNode.nodeForObject(Kernel).class.should == ModNode
    #ObjectNode.nodeForObject(NSImage.alloc.init).class.should == NSImageNode
  end
end

describe "An ObjectNode instance" do
  before do
    @object = AnObject.new
    @node = ObjectNode.alloc.initWithObject(@object)
  end

  it "returns a formatted result string, of the object, as value" do
    @node.objectDescription.should == IRB.formatter.result(@object)
  end

  it "returns the objects id" do
    @node.objectIDNode.value.should == "ID: #{@object.object_id}"
  end

  it "returns a ModNode for this object’s class" do
    @node.classNode.should == ModNode.alloc.initWithObject(@object.class, value: "Class: AnObject")
  end

  it "returns a BlockListNode with public method names, only define on the object's class" do
    @node.publicMethodsNode.to_s.should == "Public methods"
    @node.publicMethodsNode.children.should ==
      [BasicNode.alloc.initWithValue(:an_instance_method)]
  end

  it "returns nil if there are no public methods defined on the object's class" do
    @node = ObjectNode.alloc.initWithObject(AnObjectWithoutInstanceMethods.new)
    @node.publicMethodsNode.should == nil
  end

  it "returns a BlockListNode with Objective-C method names, only defined on the object's class" do
    objc = NSAttributedString.alloc.initWithString("42")
    @node = ObjectNode.alloc.initWithObject(objc)
    @node.objcMethodsNode.to_s.should == "Objective-C methods"

    methods = objc.methods(false, true) - objc.methods(false)
    @node.objcMethodsNode.children.should == methods.map do |name|
      BasicNode.alloc.initWithValue(name)
    end
  end

  it "returns a BlockListNode with the object's instance variables" do
    @node.instanceVariablesNode.should == nil

    @object.instance_variable_set(:@an_instance_variable, :ok)
    @node.instanceVariablesNode.children.should == [
      ObjectNode.alloc.initWithObject(:ok, value: :@an_instance_variable)
    ]
  end

  it "collects all children nodes, without nil values" do
    def @node.called; @called ||= []; end

    def @node.descriptionNode;       called << :descriptionNode;       nil;                    end
    def @node.classNode;             called << :classNode;             :classNode;             end
    def @node.objectIDNode;          called << :objectIDNode;          :objectIDNode;          end
    def @node.publicMethodsNode;     called << :publicMethodsNode;     :publicMethodsNode;     end
    def @node.objcMethodsNode;       called << :objcMethodsNode;       nil;                    end
    def @node.instanceVariablesNode; called << :instanceVariablesNode; :instanceVariablesNode; end

    @node.children.should == [:classNode, :objectIDNode, :publicMethodsNode, :instanceVariablesNode]
    @node.called.should ==   [:descriptionNode, :classNode, :objectIDNode, :publicMethodsNode, :objcMethodsNode, :instanceVariablesNode]
  end
end

describe "An ObjectNode instance, initialized with a value" do
  before do
    @object = AnObject.new
    @node = ObjectNode.alloc.initWithObject(@object, value: "An object")
  end

  it "returns the value it was initialized with, wrapped in an achor tag" do
    @node.value.should == "<a href='#'>An object</a>"
  end

  it "returns a descriptionNode" do
    @node.descriptionNode.children.should ==
      [BasicNode.alloc.initWithValue(@node.objectDescription)]
  end
end

describe "An ObjectNode instance, initialized without a value" do
  before do
    @object = AnObject.new
    @node = ObjectNode.alloc.initWithObject(@object)
  end

  it "returns the object description as the value" do
    @node.value.should == @node.objectDescription
  end

  it "returns nil as description node" do
    @node.descriptionNode.should == nil
  end
end

describe "ModNode" do
  it "is a subclass of ObjectNode" do
    ModNode.superclass.should == ObjectNode
  end

  it "returns the mod type" do
    node = ModNode.alloc.initWithObject(String)
    node.modTypeNode.should == BasicNode.alloc.initWithValue("Type: Class")

    node = ModNode.alloc.initWithObject(Kernel)
    node.modTypeNode.should == BasicNode.alloc.initWithValue("Type: Module")
  end

  it "returns the ancestors" do
    node = ModNode.alloc.initWithObject(String)
    node.ancestorNode.value.should == "Ancestors"
    node.ancestorNode.children.should == String.ancestors[1..-1].map do |mod|
      ModNode.alloc.initWithObject(mod, value: mod.name)
    end
  end

  it "returns a list of children" do
    ModNode.children.should == [
      :modTypeNode, :ancestorNode,
      :publicMethodsNode, :objcMethodsNode,
      :instanceVariablesNode
    ]
  end
end

#describe "NSImageNode" do
  #before do
    #@image = NSImage.imageNamed('NSNetwork')
    #@node = NSImageNode.alloc.initWithObject(@image)
  #end
#end
