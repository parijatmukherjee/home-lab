import { useEffect, useState } from "react";
import MatrixRain from "@/components/MatrixRain";
import LoginTerminal from "@/components/LoginTerminal";

const Index = () => {
  const [showContent, setShowContent] = useState(false);
  const [userIp, setUserIp] = useState<string>("");

  useEffect(() => {
    const timer = setTimeout(() => setShowContent(true), 500);
    return () => clearTimeout(timer);
  }, []);

  useEffect(() => {
    // Fetch user's real IP address
    const fetchIp = async () => {
      try {
        const response = await fetch("https://api.ipify.org?format=json");
        const data = await response.json();
        setUserIp(data.ip);
      } catch (error) {
        console.error("Failed to fetch IP:", error);
        setUserIp("UNKNOWN");
      }
    };

    fetchIp();
  }, []);

  return (
    <div className="relative min-h-screen overflow-hidden bg-background">
      <MatrixRain />
      
      {/* Scan lines overlay */}
      <div className="fixed inset-0 pointer-events-none opacity-10" style={{ zIndex: 2 }}>
        <div className="absolute inset-0" style={{
          backgroundImage: "repeating-linear-gradient(0deg, transparent, transparent 2px, rgba(0, 255, 65, 0.03) 2px, rgba(0, 255, 65, 0.03) 4px)"
        }} />
      </div>

      <main className="relative z-10 min-h-screen px-4 py-8">
        {showContent && (
          <div className="container mx-auto min-h-screen flex flex-col justify-center">
            {/* Two Column Layout */}
            <div className="grid lg:grid-cols-2 gap-8 lg:gap-12 items-center">

              {/* Left Side - Text Content */}
              <div className="space-y-6 lg:pr-8">
                <div className="space-y-3">
                  <div className="text-primary text-sm font-mono tracking-widest">
                    &gt; INITIALIZING CORE SYSTEMS...
                  </div>
                  <h2 className="text-2xl md:text-3xl lg:text-4xl font-bold text-foreground matrix-text">
                    WELCOME TO THE MOHJAVE MAINFRAME
                  </h2>
                  <p className="text-muted-foreground text-xs md:text-sm font-mono italic">
                    "What you must learn is that these rules are no different than the rules of a computer system..."
                  </p>
                  <p className="text-primary text-xs md:text-sm font-mono">
                    &gt; Some of them can be bent. Others can be broken.
                  </p>
                </div>

                <div className="glitch-effect">
                  <h1 className="text-4xl md:text-6xl lg:text-7xl font-bold text-primary matrix-text mb-4">
                    ACCESS DENIED
                  </h1>
                </div>

                <div className="space-y-4">
                  <p className="text-lg md:text-xl lg:text-2xl text-foreground matrix-text">
                    "You're not supposed to be here, Neo."
                  </p>

                  <div className="bg-card/30 border border-danger p-4 backdrop-blur-sm">
                    <p className="text-danger text-sm font-mono">
                      [!] WARNING: This is a restricted area
                    </p>
                    <p className="text-muted-foreground text-xs font-mono mt-2">
                      &gt; Unauthorized personnel will be reported
                    </p>
                    <p className="text-muted-foreground text-xs font-mono">
                      &gt; Your IP has been logged: {userIp || "Detecting..."}
                    </p>
                    <p className="text-muted-foreground text-xs font-mono">
                      &gt; Security protocols: ACTIVE
                    </p>
                  </div>

                  <p className="text-foreground text-sm italic font-mono">
                    But since you're already here... might as well try logging in.
                    <br />
                    <span className="text-muted-foreground">(Spoiler: It won't work)</span>
                  </p>
                </div>
              </div>

              {/* Right Side - Login Component */}
              <div className="flex items-center justify-center lg:pl-8">
                <div className="w-full max-w-md">
                  <LoginTerminal />
                </div>
              </div>

            </div>

            {/* Footer */}
            <footer className="mt-6 text-center space-y-2">
              <p className="text-muted-foreground text-xs font-mono">
                &gt; core.mohjave.com | System v2.0.77
              </p>
              <p className="text-muted-foreground text-xs font-mono">
                &gt; "I know Kung Fu... and Bash scripting."
              </p>
              <p className="text-foreground text-xs font-mono mt-4">
                &gt; Crafted by{" "}
                <a
                  href="https://github.com/parijatmukherjee"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-primary hover:text-primary/80 transition-colors hover:shadow-[0_0_10px_rgba(0,255,65,0.5)]"
                >
                  Parijat Mukherjee
                </a>
              </p>
            </footer>
          </div>
        )}
      </main>
    </div>
  );
};

export default Index;
