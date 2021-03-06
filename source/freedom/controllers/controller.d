
module freedom.controllers.controller;

import std.algorithm;
import std.array;
import std.string;
import std.traits;
import std.typecons;

import vibe.inet.url;
import vibe.http.server;

struct Resource
{
private:
    string _path;

public:
    this(string path)
    {
        _path = path;
    }

    Resource join(Resource other)
    {
        if(_path[$ - 1] == '/')
        {
            return Resource(_path[0 .. $ - 1] ~ other.path);
        }
        else
        {
            return Resource(_path ~ other.path);
        }
    }

    @property
    string path()
    {
        return _path.length && _path[0] != '/' ? "/" ~ _path : _path;
    }
}

alias RequestHandler = void function(HTTPServerRequest, HTTPServerResponse);

abstract class Controller
{
    mixin HTTPMethods;

protected:
    static struct After
    {
    private:
        string[] _actions = [ "*" ];

    public:
        this(string[] actions...)
        {
            _actions = actions.dup;
        }

        bool matches(string target)
        {
            foreach(action; _actions)
            {
                if(action == target || action == "*")
                {
                    return true;
                }
            }

            return false;
        }
    }

    static struct Before
    {
    private:
        string[] _actions = [ "*" ];

    public:
        this(string[] actions...)
        {
            _actions = actions.dup;
        }

        bool matches(string target)
        {
            foreach(action; _actions)
            {
                if(action == target || action == "*")
                {
                    return true;
                }
            }

            return false;
        }
    }

    static struct Catch
    {
    }

private:
    string _action;
    HTTPServerRequest _request;
    HTTPServerResponse _response;

public:
    @property
    string action()
    {
        return _action;
    }

    void redirect(string url, int status = 302)
    {
        response.redirect(url, status);
    }

    void redirect(URL url, int status = 302)
    {
        response.redirect(url, status);
    }

    @property
    void render(string templateFile, Aliases...)()
    {
        response.render!(templateFile, Aliases);
    }

    @property
    HTTPServerRequest request()
    {
        return _request;
    }

    @property
    HTTPServerResponse response()
    {
        return _response;
    }
}

package
{
    mixin template HTTPMethods()
    {
        private static string httpMethodsSource()
        {
            string result = "";

            foreach(name; __traits(allMembers, HTTPMethod))
            {
                result ~= "alias " ~ name ~ " = HTTPMethod." ~ name ~ ";";
            }

            return result;
        }

        mixin(httpMethodsSource);
    }

    struct ResourceDescriptor
    {
        string name;
        Resource resource;
        HTTPMethod[] httpMethods;
        RequestHandler requestHandler;
    }

    @property
    string defaultResourcePath(string name)
    {
        switch(name)
        {
            case "index":
            case "create":
                return "/";
            case "show":
            case "update":
            case "destroy":
                return "/:id";
            default:
                return name;
        }
    }

    void fireAfterCallbacks(Type : Controller)(Type controller)
    {
        foreach(name; __traits(derivedMembers, Type))
        {
            static if(isAfterFunction!(Type, name))
            {
                alias after = getUDAs!(__traits(getMember, Type, name), Controller.After);

                static if(after.length > 0)
                {
                    foreach(descriptor; after)
                    {
                        if(descriptor.matches(controller.action))
                        {
                            __traits(getMember, controller, name)();
                            break;
                        }
                    }
                }
                else
                {
                    __traits(getMember, controller, name)();
                }
            }
        }
    }

    void fireBeforeCallbacks(Type : Controller)(Type controller)
    {
        foreach(name; __traits(derivedMembers, Type))
        {
            static if(isBeforeFunction!(Type, name))
            {
                alias before = getUDAs!(__traits(getMember, Type, name), Controller.Before);

                static if(before.length > 0)
                {
                    foreach(descriptor; before)
                    {
                        if(descriptor.matches(controller.action))
                        {
                            __traits(getMember, controller, name)();
                            break;
                        }
                    }
                }
                else
                {
                    __traits(getMember, controller, name)();
                }
            }
        }
    }

    bool fireCatchCallbacks(Type : Controller)(Type controller, Throwable throwable)
    {
        foreach(name; __traits(derivedMembers, Type))
        {
            static if(isCatchFunction!(Type, name))
            {
                alias params = Parameters!(__traits(getMember, Type, name));
                auto exception = cast(params[0]) throwable;

                if(exception !is null)
                {
                    __traits(getMember, controller, name)(exception);
                    return true;
                }
            }
        }

        return false;
    }

    @property
    HTTPMethod[] httpMethods(Type : Controller, string name)()
    {
        HTTPMethod[] methods;

        foreach(method; EnumMembers!HTTPMethod)
        {
            static if(hasUDA!(__traits(getMember, Type, name), method))
            {
                methods ~= method;
            }
        }

        if(methods.length == 0)
        {
            methods ~= HTTPMethod.GET;
        }
        else
        {
            methods = sort(methods).uniq.array;
        }

        return methods;
    }

    @property
    template isAfterFunction(Type : Controller, string name)
    {
        static if(isPublicFunction!(Type, name))
        {
            enum isAfterFunction = hasUDA!(__traits(getMember, Type, name), Controller.After);
        }
        else
        {
            enum isAfterFunction = false;
        }
    }

    @property
    template isBeforeFunction(Type : Controller, string name)
    {
        static if(isPublicFunction!(Type, name))
        {
            enum isBeforeFunction = hasUDA!(__traits(getMember, Type, name), Controller.Before);
        }
        else
        {
            enum isBeforeFunction = false;
        }
    }

    @property
    template isCatchFunction(Type : Controller, string name)
    {
        static if(isPublicFunction!(Type, name))
        {
            alias params = Parameters!(__traits(getMember, Type, name));

            static if(params.length == 1)
            {
                enum isCatchFunction = is(params[0] : Throwable);
            }
            else
            {
                enum isCatchFunction = false;
            }
        }
        else
        {
            enum isCatchFunction = false;
        }
    }

    @property
    template isPublicFunction(Type : Controller, string name)
    {
        static if(__traits(hasMember, Type, name))
        {
            static if(__traits(getProtection, __traits(getMember, Type, name)) == "public")
            {
                enum isPublicFunction = is(typeof(__traits(getMember, Type, name)) == function);
            }
            else
            {
                enum isPublicFunction = false;
            }
        }
        else
        {
            enum isPublicFunction = false;
        }
    }

    @property
    template isResourceFunction(Type : Controller, string name)
    {
        static if(isPublicFunction!(Type, name))
        {
            enum isResourceFunction = hasUDA!(__traits(getMember, Type, name), Resource);
        }
        else
        {
            enum isResourceFunction = false;
        }
    }

    @property
    RequestHandler requestHandler(Type : Controller, string name)()
    {
        return function void(HTTPServerRequest request, HTTPServerResponse response)
        {
            Type controller = new Type;

            controller._action = name;
            controller._request = request;
            controller._response = response;

            try
            {
                // Fire before-action callbacks.
                controller.fireBeforeCallbacks;

                __traits(getMember, controller, name)();

                // Fire after-action callbacks.
                controller.fireAfterCallbacks;
            }
            catch(Throwable throwable)
            {
                // Fire exception-handler callbacks.
                if(!controller.fireCatchCallbacks(throwable))
                {
                    // Re-throw.
                    throw throwable;
                }
            }
        };
    }

    template resource(Type : Controller)
    {
        static if(hasUDA!(Type, Resource))
        {
            alias resourceUDAs = getUDAs!(Type, Resource);
            static assert(resourceUDAs.length == 1, Type.stringof ~ " may only declare one resource id.");

            enum Resource resource = resourceUDAs[0];
        }
        else
        {
            enum string typeName = Type.stringof;

            static if(typeName.endsWith("Controller"))
            {
                enum Resource resource = Resource(typeName[0 .. $ - "Controller".length].toLower);
            }
            else
            {
                enum Resource resource = Resource(typeName.toLower);
            }
        }
    }

    @property
    template resource(Type : Controller, string name)
    {
        static if(isResourceFunction!(Type, name))
        {
            alias resourceUDAs = getUDAs!(__traits(getMember, Type, name), Resource);

            static if(resourceUDAs.length > 0)
            {
                enum Resource resource = resourceUDAs[0];
            }
            else
            {
                enum Resource resource = Resource(name.defaultResourcePath.toLower);
            }
        }
        else
        {
            static assert(0, Type.stringof ~ "." ~ name ~ " is not a resource.");
        }
    }

    @property
    ResourceDescriptor[] resources(Type : Controller)()
    {
        ResourceDescriptor[] resources;

        foreach(name; __traits(derivedMembers, Type))
        {
            static if(isResourceFunction!(Type, name))
            {
                resources ~= ResourceDescriptor(
                    name,
                    resource!(Type, name),
                    httpMethods!(Type, name),
                    requestHandler!(Type, name)
                );
            }
        }

        return resources;
    }
}
