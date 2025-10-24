import { useEffect } from "react";
import { useNavigate } from "react-router-dom";
import MatrixRain from "@/components/MatrixRain";

const Dashboard = () => {
  const navigate = useNavigate();

  useEffect(() => {
    const isAuthenticated = sessionStorage.getItem("authenticated");
    if (!isAuthenticated) {
      navigate("/");
    }
  }, [navigate]);

  const handleLogout = () => {
    sessionStorage.removeItem("authenticated");
    navigate("/");
  };

  const services = [
    {
      name: "Jenkins CI/CD",
      url: "http://jenkins.core.mohjave.com",
      description: "Continuous Integration and Deployment",
    },
    {
      name: "Artifact Repository",
      url: "http://artifacts.core.mohjave.com",
      description: "Build artifacts and packages",
    },
    {
      name: "Monitoring Dashboard",
      url: "http://monitoring.core.mohjave.com",
      description: "System monitoring with Netdata",
    },
  ];

  return (
    <div className="relative min-h-screen overflow-hidden bg-background">
      <MatrixRain />

      {/* Scan lines overlay */}
      <div className="fixed inset-0 pointer-events-none opacity-10" style={{ zIndex: 2 }}>
        <div
          className="absolute inset-0"
          style={{
            backgroundImage:
              "repeating-linear-gradient(0deg, transparent, transparent 2px, rgba(0, 255, 65, 0.03) 2px, rgba(0, 255, 65, 0.03) 4px)",
          }}
        />
      </div>

      <main className="relative z-10 flex flex-col items-center justify-center min-h-screen px-4 py-12">
        <div className="w-full max-w-4xl">
          <div className="text-center mb-12">
            <h1 className="text-5xl md:text-6xl font-bold text-primary matrix-text mb-4">
              ACCESS GRANTED
            </h1>
            <p className="text-xl text-foreground matrix-text">
              Welcome to the Mohjave Core Systems
            </p>
          </div>

          <div className="grid md:grid-cols-3 gap-6 mb-8">
            {services.map((service) => (
              <a
                key={service.name}
                href={service.url}
                target="_blank"
                rel="noopener noreferrer"
                className="border-2 border-primary p-6 backdrop-blur-sm bg-card/50 hover:bg-card/70 transition-all hover:shadow-lg hover:shadow-primary/50"
              >
                <h3 className="text-xl font-bold text-primary matrix-text mb-2">
                  {service.name}
                </h3>
                <p className="text-muted-foreground text-sm font-mono">
                  {service.description}
                </p>
                <p className="text-primary text-xs font-mono mt-4">
                  &gt; ACCESS_LINK
                </p>
              </a>
            ))}
          </div>

          <div className="text-center">
            <button
              onClick={handleLogout}
              className="border-2 border-danger text-danger px-6 py-2 font-mono hover:bg-danger hover:text-background transition-all"
            >
              &gt; LOGOUT
            </button>
          </div>

          <footer className="mt-12 text-center space-y-2">
            <p className="text-muted-foreground text-xs font-mono">
              &gt; core.mohjave.com | System v2.0.77
            </p>
            <p className="text-muted-foreground text-xs font-mono">
              &gt; "Welcome to the real world."
            </p>
          </footer>
        </div>
      </main>
    </div>
  );
};

export default Dashboard;
