import { useEffect, useState } from "react";
import MatrixRain from "@/components/MatrixRain";
import LoginTerminal from "@/components/LoginTerminal";

const Index = () => {
  const [showContent, setShowContent] = useState(false);

  useEffect(() => {
    const timer = setTimeout(() => setShowContent(true), 500);
    return () => clearTimeout(timer);
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

      <main className="relative z-10 flex flex-col items-center justify-center min-h-screen px-4 py-12">
        {showContent && (
          <>
            <div className="text-center mb-12 space-y-6 max-w-2xl">
              <div className="glitch-effect">
                <h1 className="text-5xl md:text-7xl font-bold text-primary matrix-text mb-4">
                  ACCESS DENIED
                </h1>
              </div>
              
              <div className="space-y-4">
                <p className="text-xl md:text-2xl text-foreground matrix-text">
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
                    &gt; Your IP has been logged: {Math.floor(Math.random() * 255)}.{Math.floor(Math.random() * 255)}.{Math.floor(Math.random() * 255)}.{Math.floor(Math.random() * 255)}
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

            <LoginTerminal />

            <footer className="mt-12 text-center space-y-2">
              <p className="text-muted-foreground text-xs font-mono">
                &gt; core.mohjave.com | System v2.0.77
              </p>
              <p className="text-muted-foreground text-xs font-mono">
                &gt; "There is no spoon. But there is a login form."
              </p>
            </footer>
          </>
        )}
      </main>
    </div>
  );
};

export default Index;
