require 'gserver'
require 'socket'
require 'glint'

describe GServer do


  before :each do
    @host = ENV['RUBY_GSERVER_HOST'] || '127.0.0.1'
    @port = ENV['RUBY_GSERVER_PORT'] || Glint::Util.empty_port.to_s
    @server_class = Class.new(GServer) do
      def serve(io)
        IO.select([io], nil, nil, 60)
        io.readline
        io.print("#{self.connections}\r\n")
        io.close
      end
    end
  end


  describe "limit max connections" do

    let(:precision){ (ENV['RUBY_GSERVER_PRECISION'] || '100').to_i }

    before :each do
      ppid = $$
      ready = false
      backup_parent_sighup = trap :HUP, proc { ready = true }
      @pid = fork {

        # create a server with maxConnections
        @server = @server_class.new(@port, @host, maxConnections)

        # install shutdown procedure
        backup_child_sigint = trap :INT, proc {
          @server.shutdown
          @server.instance_variable_get(:@tcpServer).close
        }

        # start server and notify parent
        @server.start
        Process.kill :HUP, ppid
        @server.join

        # restore signal for child
        trap :INT, backup_child_sigint
      }

      # wait until server in child readies
      limit_waiting = (ENV['RUBY_GSERVER_WAIT'] || '10').to_i
      interval = 0.5
      elapsed = 0 - interval
      while ! ready do
        elapsed += interval
        raise "could not start a server" if limit_waiting <= elapsed
        sleep interval
      end

      # restore signal for parent
      trap :HUP, backup_parent_sighup
    end

    after :each do
      # shutdonw server gracefully
      if @pid
        Process.kill :INT, @pid 
        Process.waitpid @pid
      end
    end

    shared_examples "max connections" do
      it {
        answers = []
        precision.times {
          # create 1 + maxConnections clients
          c = TCPSocket.open(@host, @port)
          clients = []
          maxConnections.times {
            clients << TCPSocket.open(@host, @port)
          }

          IO.select(nil, [c], nil, 60)
          c.print("how many connections?\r\n")

          IO.select([c], nil, nil, 60)
          answers << c.gets.chomp.to_i

          c.close
          clients.each {|c| c.close }
        }

        expect( answers.size ).to eq precision
        expect( answers.find_all{|i| 0 < i }.size ).to eq precision
        expect( answers.find_all{|i| i <= maxConnections }.size ).to eq precision
      }
    end

    context do
      let(:maxConnections){ 4 }
      it_behaves_like "max connections"
    end

  end # describe "limit max connections"

end
