
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

    void bind(Type : Controller)()
    {
        auto child = new URLRouter;

        foreach(res; resources!Type)
        {
            string path = resource!Type.join(res[0]).path;

            foreach(HTTPMethod method; res[1])
            {
                child.match(method, path, res[2]);
            }
        }

        _root.any(resource!Type.path ~ "/*", child);
    }

    void handleRequest(HTTPServerRequest request, HTTPServerResponse response)
    {
        _root.handleRequest(request, response);
    }
}
