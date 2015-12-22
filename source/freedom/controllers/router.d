
module freedom.controllers.router;

import vibe.http.router;
import vibe.http.server;

import freedom.controllers.controller;

class ControllerRouter : HTTPServerRequestHandler
{
private:
    URLRouter _root;

public:
    this()
    {
        _root = new URLRouter;
    }

    void bind(Ctrl : Controller)()
    {
        auto child = new URLRouter;
        scope auto controller = new Ctrl;

        foreach(resource; controller.resources)
        {
            string path = controller.resource.join(resource[0]).path;

            foreach(HTTPMethod method; resource[1])
            {
                child.match(method, path, resource[2]);
            }
        }

        _root.any(controller.resource.path ~ "/*", child);
    }

    void handleRequest(HTTPServerRequest request, HTTPServerResponse response)
    {
        _root.handleRequest(request, response);
    }
}
