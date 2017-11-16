
enum VoidVisib
    PUBLIC PROTECTED PRIVATE 
end
class LinCAS::Parser < LinCAS::MsgGenerator
    
    START_SYNC_SET = 
    { TkType::IF, TkType::SELECT, TkType::DO, TkType::FOR,
      TkType::PUBLIC, TkType::PROTECTED, TkType::PRIVATE,
      TkType::VOID, TkType::CLASS, TkType::MODULE, TkType::REQUIRE,
      TkType::INCLUDE, TkType::USE, TkType::CONST, TkType::GLOBAL_ID,
      TkType::LOCAL_ID
    }


    def initialize(@scanner : Scanner)
        @nestedVoids = 0
        @sym         = false
        @currentTk   = @scanner.currentTk.as(Token)
        @nextTk      = @scanner.nextTk.as(Token)
        @nodeFactory = IntermediateFactory.new
        @msgHandler  = MsgHandler.new
        @errHandler  = ErrorHandler.new
        @withSummary = true
        @tokenDisplay = false
        @dummyCount  = 0
        @lineSet     = true
        @cm          = 0
    end

    def messageHandler
        @msgHandler
    end

    def filename
        return @scanner.filename
    end

    def noSummary
        @withSummary = false
    end

    def displayTokens
        @tokenDisplay = true
    end

    def sourceLines
        @scanner.lines
    end

    protected def sync(syncSet)
        if !(syncSet.includes? @currentTk.ttype)
            @errHandler.flag(@currentTk,ErrCode::UNEXPECTED_TOKEN,self)
            while !(syncSet.includes? @currentTk.ttype)
                shift
                if @currentTk.ttype == TkType::ERROR
                    @errHandler.flag(@currentTk,@currentTk.value,self)
                    shift
                end
            end   
        end
    end

    protected def shift
        @currentTk = @nextTk
        @nextTk = @scanner.nextTk
    end

    protected def skipEol
        while @currentTk.ttype == TkType::EOL
            shift
        end
    end

    def parse
        nowTime = Time.now.millisecond
        if @tokenDisplay
            while !(@currentTk.is_a? EofTk)
                if @currentTk.ttype != TkType::ERROR
                    body = {@currentTk.ttype.to_s,
                            @currentTk.text,
                            (@currentTk.value? ? @currentTk.value.to_s : nil.to_s),
                            @currentTk.line.to_s,
                            @currentTk.pos.to_s}.to_a
                    msg = Msg.new(MsgType::TOKEN,body)
                    sendMsg(msg)
                else
                    @errHandler.flag(@currentTk,@currentTk.value,self)
                end
                shift
            end
        else
            return parseProgram
        end
        if @withSummary
            time = Time.now.millisecond - nowTime
            msg = Msg.new(MsgType::PARSER_SUMMARY,[@scanner.lines.to_s,
                                                   @errHandler.errors.to_s,
                                                   time.to_s])
            sendMsg(msg)
        end
    end

    protected def parseProgram : Node
        program = @nodeFactory.makeNode(NodeType::PROGRAM)
        while !(@currentTk.is_a? EofTk)
            if !(@currentTk.ttype == TkType::ERROR)
                node = parseStmts
                program.addBranch(node)
            else
                @errHandler.flag(@currentTk,@currentTk.value,self)
            end
        end 
        program.setAttr(NKey::FILENAME,@scanner.filename)
        return program
    end

    protected def parseStmts : Node
        sync(START_SYNC_SET)
        tkType = @currentTk.ttype
        case tkType
            when TkType::CLASS
                return parseClass
            when TkType::MODULE
                return parseModule
            when TkType::VOID
                return parseVoid
            when TkType::PRIVATE, TkType::PROTECTED,  TkType::PUBLIC
                return parseVisibility
            #when TkType::SELECT
            #when TkType::DO
            #when TkType::IF 
            #when TkType::FOR
            #when TkType::GLOBAL_ID, TkType::LOCAL_ID, TkType::FLOAT, TkType::INT,
            #      TkType::TAN, TkType::ATAN, TkType::LOG, TkType::EXP, TkType::COS,
            #      TkType::ACOS, TkType::SIN, TkType::ASIN, TkType::SQRT
            #when 
            #when TkType::CONST
            #when TkType::INCLUDE
            #when TkType::REQUIRE
            #when TkType::USE
            #when TkType::RETURN
            else
                return @nodeFactory.makeNode(NodeType::NOOP)
        end
    ensure
        checkEol
    end
    
    protected def parseClass : Node
        @errHandler.flag(@currentTk,ErrCode::CLASS_IN_VOID,self) if @nestedVoids > 0
        class_sync_set = 
        { 
            TkType::LOCAL_ID, TkType::INHERITS, TkType::L_BRACE, TkType::EOL
        }
        mid_sync_set =
        {
            TkType::LOCAL_ID, TkType::L_BRACE, TkType::EOL
        }
        @cm += 1
        node = @nodeFactory.makeNode(NodeType::CLASS)
        setLine(node)
        shift
        sync(class_sync_set)
        name = parseName
        node.setAttr(NKey::NAME,name)
        sync(class_sync_set)
        if @currentTk == TkType::INHERITS
            shift
            sync(mid_sync_set)
            if @currentTk.ttype == TkType::LOCAL_ID
                parent = parseNameSpace
            else
                @errHandler.flag(@currentTk,ErrCode::MISSING_IDENT,self)
                parent = makeDummyName
            end
            node.setAttr(NKey::PARENT,parent)
        else
            parent = @nodeFactory.makeNode(NodeType::LOCAL_ID)
            parent.setAttr(NKey::ID,"Object")
            node.setAttr(NKey::PARENT,parent)
            node.addBranch(parseBody)
        end
        @cm -= 1
        return node 
    end

    protected def parseModule : Node
        @errHandler.flag(@currentTk,ErrCode::MODULE_IN_VOID,self) if @nestedVoids > 0
        module_sync_set = 
        {
            TkType::LOCAL_ID, TkType::L_BRACE, TkType::EOL
        }
        @cm += 1
        node = @nodeFactory.makeNode(NodeType::MODULE)
        setLine(node)
        shift
        sync(module_sync_set)
        node.setAttr(NKey::NAME,parseName)
        node.addBranch(parseBody)
        @cm -= 1
        return node
    end

    private def parseName : Node
        if @currentTk.ttype == TkType::LOCAL_ID
            name = parseNameSpace
        else
            @errHandler.flag(@currentTk,ErrCode::MISSING_IDENT,self)
            name = makeDummyName
        end
        return name
    end

    protected def parseVoid : Node
        void_sync_set =
        {
            TkType::SELF, TkType::LOCAL_ID, TkType::L_PAR, 
            TkType::SEMICOLON, TkType::EOL
        }
        @nestedVoids += 1
        node = @nodeFactory.makeNode(NodeType::VOID)
        if @lineSet
            setLine(node) 
        else
            @lineSet = !@lineSet
        end 
        shift
        sync(void_sync_set)
        name = parseVoidName
        node.setAttr(NKey::NAME,name)
        sync(void_sync_set)
        node.addBranch(parseVoidArgList)
        node.addBranch(parseBody)
        @nestedVoids -= 1
        return node
    end

    protected def parseVisibility : Node
        visibility = @currentTk
        shift
        @lineSet = false
        if !(@currentTk.ttype == TkType::VOID)
            @errHandler.flag(@currentTk,ErrCode::INVALID_VISIB_ARG,self)
            return parseStmts
        else
            void = parseVoid
        end
        case visibility.ttype
            when TkType::PUBLIC
                void.setAttr(NKey::VOID_VISIB,VoidVisib::PUBLIC)
            when TkType::PROTECTED
                @errHandler.flag(visibility,ErrCode::UNALLOWED_PROTECTED,self) unless @cm > 0
                void.setAttr(NKey::VOID_VISIB,VoidVisib::PUBLIC)
            when TkType::PRIVATE
                void.setAttr(NKey::VOID_VISIB,VoidVisib::PRIVATE)
        end
        return void 
    end

    protected def parseVoidName : Node
        name_sync_set = 
        {
            TkType::LOCAL_ID, TkType::L_PAR, TkType::SEMICOLON, TkType::EOL
        }
        if @currentTk == TkType::SELF
            node = @nodeFactory.makeNode(NodeType::SELF)
            shift
            if @currentTk.ttype == TkType::DOT 
                shift
            else
                @errHandler.flag(@currentTk,ErrCode::MISSING_DOT,self)
            end
            sync(name_sync_set)
            if @currentTk.ttype == TkType::LOCAL_ID
                node.addBranch(parseLocalID)
            else
                @errHandler.flag(@currentTk,ErrCode::MISSING_IDENT,self)
                node.addBranch(makeDummyName)
            end 
            return node
        elsif @currentTk == TkType::LOCAL_ID
            return parseLocalID
        elsif ALLOWED_VOID_NAMES.includes? @currentTk.text
            node = @nodeFactory.makeNode(NodeType::OPERATOR)
            node.setAttr(NKey::ID,@currentTk.text)
            return node
        else
            @errHandler.flag(@currentTk,ErrCode::MISSING_IDENT,self)
            return makeDummyName
        end
    end

    protected def parseVoidArgList
        node = @nodeFactory.makeNode(NodeType::ARG_LIST)
        # To implement
    end

    protected def parseBody : Node
        body_sync_set = {TkType::L_BRACE} + START_SYNC_SET
        node = @nodeFactory.makeNode(NodeType::BODY)
        skipEol
        sync(body_sync_set)
        if !(@currentTk.ttype == TkType::L_BRACE)
            @errHandler.flag(@currentTk,ErrCode::MISSING_L_BRACE,self)
        else
            shift
        end
        while (@currentTk.ttype != TkType::R_BRACE) && !(@currentTk.is_a? EofTk)
            node.addBranch(parseStmts)
        end
        if !(@currentTk.ttype == TkType::L_BRACE)
            @errHandler.flag(@currentTk,ErrCode::MISSING_L_BRACE,self)
        elsif @currentTk.is_a? EofTk
            @errHandler.flag(@currentTk,ErrCode::UNEXPECTED_EOF,self)
            @errHandler.abortProcess
        else
            shift
        end 
        return node
    end

    protected def parseNameSpace : Node
        node = @nodeFactory.makeNode(NodeType::NAMESPACE)
        # To Implement
    end

    protected def parseLocalID : Node
        node = @nodeFactory.makeNode(NodeType::LOCAL_ID)
        node.setAttr(NKey::ID,@currentTk.text)
        return node
    end

    protected def checkEol : ::Nil
        if (@currentTk.ttype == TkType::SEMICOLON) || (@currentTk.is_a? EolTk)
            shift
        else
            @errHandler.flag(@currentTk,ErrCode::MISSING_EOL,self)
        end
    end

    private def makeDummyName : Node
        node = @nodeFactory.makeNode(NodeType::LOCAL_ID)
        node.setAttr(NKey::ID,"DummyName_#{@dummyCount += 1}")
        return node
    end

    private def setLine(node : Node) : ::Nil
        node.setAttr(NKey::LINE,@currentTk.line)
    end
    
end