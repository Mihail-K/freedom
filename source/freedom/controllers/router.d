
module freedom.controllers.router;

import std.algorithm;

import vibe.http.router;
import vibe.http.server;

import freedom.controllers.controller;

class ControllerRouter : HTTPServerRequestHandler
{
private:
    URLRouter _root;

public:
    this(string prefix = null)
    {
        _root = new URLRouter(prefix);
    }

    ControllerRouter route(Type : Controller)(string[] filter = null...)
    {
        auto parent = new URLRouter(resource!Type.path);

        foreach(descriptor; resources!Type)
        {
            // Check if mapping for this resource is permitted.
            if(!filter || filter.countUntil(descriptor.name) != -1)
            {
                string path = descriptor.resource.path;

                foreach(HTTPMethod method; descriptor.httpMethods)
                {
                    parent.match(method, path, descriptor.requestHandler);
                }
            }
        }

        _root.any(resource!Type.path ~ "*", parent);
        return this;
    }

    void handleRequest(HTTPServerRequest request, HTTPServerResponse response)
    {
        _root.handleRequest(request, response);
    }
}
