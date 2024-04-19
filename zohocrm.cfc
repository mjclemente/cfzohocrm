/**
 * CFZohoCRM
 * Copyright 2024  Matthew J. Clemente, John Berquist
 * Licensed under MIT (https://mit-license.org)
 *
 * with some code adapted from https://gist.github.com/danwatt/1827874
 * with some code adapted https://gist.github.com/jeremyhalliwell/3be545da6f4ebd07d741, by Jeremy Halliwell
 * with some code adapted https://gist.github.com/mjclemente/824f58d52ed907b1fcf18789fdee80a2, by Matthew Clemente
 *
 */
component displayname="CFZohoCRM" {

    variables._cfzohocrm_version = '0.0.0';

    public any function init(
        string client_id = '',
        string client_secret = '',
        string refresh_token = '',
        string accessTokenEndpoint = 'https://accounts.zoho.com/oauth/v2/token',
        string apiVersion = '6',
        string apiDomain = 'https://www.zohoapis.com',
        boolean includeRaw = false,
        numeric httpTimeout = 50
    ) {
        structAppend(variables, arguments);
        variables.access_token = '';

        // map sensitive args to env variables or java system props
        var secrets = {
            'client_id': 'ZOHOCRM_CLIENT_ID',
            'client_secret': 'ZOHOCRM_CLIENT_SECRET',
            'refresh_token': 'ZOHOCRM_REFRESH_TOKEN'
        };
        var system = createObject('java', 'java.lang.System');

        for (var key in secrets) {
            // arguments are top priority
            if (variables[key].len()) {
                continue;
            }

            // check environment variables
            var envValue = system.getenv(secrets[key]);
            if (!isNull(envValue) && envValue.len()) {
                variables[key] = envValue;
                continue;
            }

            // check java system properties
            var propValue = system.getProperty(secrets[key]);
            if (!isNull(propValue) && propValue.len()) {
                variables[key] = propValue;
            }
        }

        // declare file fields to be handled via multipart/form-data **Important** this is not applicable if payload is application/json
        variables.fileFields = [];

        return this;
    }


    /**
     * @docs https://www.zoho.com/crm/developer/docs/api/v6/modules-api.html
     * @hint List modules
     */
    public struct function listModules() {
        return apiCall('GET', '/crm/v#variables.apiVersion#/settings/modules');
    }

    /**
     * @docs https://www.zoho.com/crm/developer/docs/api/v6/field-meta.html
     * @hint List fields for a module
     */
    public struct function listFieldsByModule(required string module) {
        var params = arguments.copy();
        return apiCall('GET', '/crm/v#variables.apiVersion#/settings/fields', params);
    }

    /**
     * @docs https://www.zoho.com/crm/developer/docs/api/v6/get-records.html
     * @hint Retrieve records that match your search criteria
     */
    public struct function getRecords(required string module) {
        var params = arguments.copy();
        params.delete('module');
        return apiCall('GET', '/crm/v#variables.apiVersion#/#arguments.module#', params);
    }

    /**
     * @docs https://www.zoho.com/crm/developer/docs/api/v6/get-records.html
     * @hint Retrieve an individual record by id
     */
    public struct function getRecordById(required string module, required string id) {
        var params = arguments.copy();
        params.delete('module');
        params.delete('id');
        return apiCall('GET', '/crm/v#variables.apiVersion#/#arguments.module#/#arguments.id#', params);
    }

    /**
     * @docs https://www.zoho.com/crm/developer/docs/api/v6/insert-records.html
     * @hint Add a new record to a module. Be sure to incude the fields required by the API. Additional arguments can be passed in to customize the request, such as `apply_feature_execution` or `trigger`. */
    public struct function insertRecord(required string module, required struct record) {
        return insertRecords(module = arguments.module, records = [arguments.record]);
    }

    /**
     * @docs https://www.zoho.com/crm/developer/docs/api/v6/insert-records.html
     * @hint Adds multiple new records to a module. Be sure to incude the fields required by the API. Additional arguments can be passed in to customize the request, such as `apply_feature_execution` or `trigger`. */
    public struct function insertRecords(required string module, required any records) {
        var data = isArray(arguments.records) ? arguments.records : [arguments.records];
        var body = {'data': data};
        var additional_data = arguments
            .copy()
            .filter((k) => {
                return !['module', 'records'].contains(k);
            });
        if (!additional_data.isEmpty()) {
            body.append(additional_data);
        }
        return apiCall(
            'POST',
            '/crm/v#variables.apiVersion#/#arguments.module#',
            {},
            body
        );
    }

    /**
     * @docs https://www.zoho.com/crm/developer/docs/api/v6/update-records.html
     * @hint Updates an existing record within a module by id
     */
    public struct function updateRecordById(required string module, required string id, required struct record) {
        return updateRecords(module = arguments.module, id = arguments.id, records = [arguments.record]);
    }

    /**
     * @docs https://www.zoho.com/crm/developer/docs/api/v6/update-records.html
     * @hint Updates existing records within a module.
     */
    public struct function updateRecords(required string module, required string id, required any records) {
        var data = isArray(arguments.records) ? arguments.records : [arguments.records];
        var body = {'data': data};
        return apiCall(
            'PUT',
            '/crm/v#variables.apiVersion#/#arguments.module#/#arguments.id#',
            {},
            body
        );
    }

    /**
     * @docs https://www.zoho.com/crm/developer/docs/api/v6/delete-records.html
     * @hint Delete an individual record by id
     */
    public struct function deleteRecordById(required string module, required string id, boolean wf_trigger) {
        var args = arguments.copy();
        args['ids'] = arguments.id;
        args.delete('id');
        return deleteRecords(argumentCollection = args);
    }

    /**
     * @docs https://www.zoho.com/crm/developer/docs/api/v6/delete-records.html
     * @hint Delete records from a module
     */
    public struct function deleteRecords(required string module, required any ids, boolean wf_trigger) {
        var params = {};
        if (!isNull(arguments.wf_trigger)) {
            params['wf_trigger'] = arguments.wf_trigger;
        }
        if (isSimpleValue(arguments.ids)) {
            return apiCall('DELETE', '/crm/v#variables.apiVersion#/#arguments.module#/#arguments.ids#', params);
        } else {
            params['ids'] = arguments.ids.toList();
            return apiCall('DELETE', '/crm/v#variables.apiVersion#/#arguments.module#', params);
        }
    }


    public string function getAccessToken() {
        return variables.access_token;
    }

    public void function logIn(boolean force = false) {
        if (variables.access_token.len() && !arguments.force) {
            return;
        }

        lock scope="application" type="exclusive" timeout="60" {
            var httpResult = '';
            cfhttp(
                method = "POST",
                timeout = 4,
                url = variables.accessTokenEndpoint,
                result = "httpResult"
            ) {
                cfhttpparam(type = "formfield", name = "grant_type", value = "refresh_token");
                cfhttpparam(type = "formfield", name = "client_id", value = variables.client_id);
                cfhttpparam(type = "formfield", name = "client_secret", value = variables.client_secret);
                cfhttpparam(type = "formfield", name = "refresh_token", value = variables.refresh_token);
            }

            if (
                httpResult.keyExists('responseHeader')
                && httpResult.responseHeader.keyExists('status_code')
                && httpResult.responseHeader.status_code == 200
            ) {
                var json = deserializeJSON(httpResult.filecontent);
                variables.apiDomain = json.api_domain;
                variables.access_token = json.access_token;
            } else {
                variables.access_token = '';
                var errorString = httpResult.filecontent;
                if (httpResult.keyExists('errordetail')) errorString &= ', detail: ' & httpResult.errordetail;
                throw(message = 'Unable to authenticate to Zoho: ' & errorString, type = 'zohoCRM.loginerror');
            }
        }
    }


    // PRIVATE FUNCTIONS
    private struct function apiCall(
        required string httpMethod,
        required string path,
        struct queryParams = {},
        any payload = '',
        struct headers = {},
        numeric attempt = 0
    ) {
        logIn(force = (arguments.attempt > 0));
        var fullApiPath = variables.apiDomain & arguments.path;
        var requestHeaders = getBaseHttpHeaders();
        requestHeaders.append(arguments.headers, true);

        var requestStart = getTickCount();
        var apiResponse = makeHttpRequest(
            httpMethod = arguments.httpMethod,
            path = fullApiPath,
            queryParams = arguments.queryParams,
            headers = requestHeaders,
            payload = arguments.payload
        );

        var result = {
            'responseTime': getTickCount() - requestStart,
            'statusCode': listFirst(apiResponse.statuscode, ' '),
            'statusText': listRest(apiResponse.statuscode, ' '),
            'headers': apiResponse.responseheader
        };
        if (result.statusCode == 401) {
            if (arguments.attempt == 0) {
                return apiCall(
                    arguments.httpMethod,
                    arguments.path,
                    arguments.queryParams,
                    arguments.payload,
                    arguments.headers,
                    1
                );
            } else {
                throw(
                    message = 'Unable to log into Zoho: ' & result.statusCode,
                    detail = apiResponse.fileContent,
                    type = 'zohoCRM.loginFailure'
                );
            }
        }

        var parsedFileContent = {};

        // Handle response based on mimetype
        var mimeType = apiResponse.mimetype ?: requestHeaders['Content-Type'];

        if (mimeType == 'application/json' && isJSON(apiResponse.fileContent)) {
            parsedFileContent = deserializeJSON(apiResponse.fileContent);
        } else if (mimeType.listLast('/') == 'xml' && isXML(apiResponse.fileContent)) {
            parsedFileContent = xmlToStruct(apiResponse.fileContent);
        } else {
            parsedFileContent = apiResponse.fileContent;
        }

        // can be customized by API integration for how errors are returned
        // if ( result.statusCode >= 400 ) {}

        // stored in data, because some responses are arrays and others are structs
        result['data'] = parsedFileContent;

        if (variables.includeRaw) {
            result['raw'] = {
                'method': uCase(arguments.httpMethod),
                'path': fullApiPath,
                'params': parseQueryParams(arguments.queryParams),
                'payload': parseBody(arguments.payload),
                'response': apiResponse.fileContent
            };
        }

        return result;
    }

    private struct function getBaseHttpHeaders() {
        return {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'Authorization': 'Bearer #getAccessToken()#',
            'User-Agent': 'CFZohoCRM/#variables._cfzohocrm_version# (ColdFusion)'
        };
    }

    private any function makeHttpRequest(
        required string httpMethod,
        required string path,
        struct queryParams = {},
        struct headers = {},
        any payload = ''
    ) {
        var result = '';

        var fullPath = path & (
            !queryParams.isEmpty()
             ? ('?' & parseQueryParams(queryParams, false))
             : ''
        );

        cfhttp(
            url = fullPath,
            method = httpMethod,
            result = "result",
            timeout = variables.httpTimeout
        ) {
            if (isJsonPayload(headers)) {
                var requestPayload = parseBody(payload);
                if (isJSON(requestPayload)) {
                    cfhttpparam(type = "body", value = requestPayload);
                }
            } else if (isFormPayload(headers)) {
                headers.delete('Content-Type'); // Content Type added automatically by cfhttppparam

                for (var param in payload) {
                    if (!variables.fileFields.contains(param)) {
                        cfhttpparam(type = "formfield", name = param, value = payload[param]);
                    } else {
                        cfhttpparam(type = "file", name = param, file = payload[param]);
                    }
                }
            }

            // handled last, to account for possible Content-Type header correction for forms
            var requestHeaders = parseHeaders(headers);
            for (var header in requestHeaders) {
                cfhttpparam(type = "header", name = header.name, value = header.value);
            }
        }
        return result;
    }

    /**
     * @hint convert the headers from a struct to an array
     */
    private array function parseHeaders(required struct headers) {
        var sortedKeyArray = headers.keyArray();
        sortedKeyArray.sort('textnocase');
        var processedHeaders = sortedKeyArray.map(function(key) {
            return {name: key, value: trim(headers[key])};
        });
        return processedHeaders;
    }

    /**
     * @hint converts the queryparam struct to a string, with optional encoding and the possibility for empty values being pass through as well
     */
    private string function parseQueryParams(
        required struct queryParams,
        boolean encodeQueryParams = true,
        boolean includeEmptyValues = true
    ) {
        var sortedKeyArray = queryParams.keyArray();
        sortedKeyArray.sort('text');

        var queryString = sortedKeyArray.reduce(function(queryString, queryParamKey) {
            var encodedKey = encodeQueryParams
             ? encodeUrl(queryParamKey)
             : queryParamKey;
            if (!isArray(queryParams[queryParamKey])) {
                var encodedValue = encodeQueryParams && len(queryParams[queryParamKey])
                 ? encodeUrl(queryParams[queryParamKey])
                 : queryParams[queryParamKey];
            } else {
                var encodedValue = encodeQueryParams && arrayLen(queryParams[queryParamKey])
                 ? encodeUrl(serializeJSON(queryParams[queryParamKey]))
                 : queryParams[queryParamKey].toList();
            }
            return queryString.listAppend(
                encodedKey & (includeEmptyValues || len(encodedValue) ? ('=' & encodedValue) : ''),
                '&'
            );
        }, '');

        return queryString.len() ? queryString : '';
    }

    private string function parseBody(required any body) {
        if (isStruct(body) || isArray(body)) {
            return serializeJSON(body);
        } else if (isJSON(body)) {
            return body;
        } else {
            return '';
        }
    }

    private string function encodeUrl(required string str, boolean encodeSlash = true) {
        var result = replaceList(urlEncodedFormat(str, 'utf-8'), '%2D,%2E,%5F,%7E', '-,.,_,~');
        if (!encodeSlash) {
            result = replace(result, '%2F', '/', 'all');
        }
        return result;
    }

    /**
     * @hint helper to determine if body should be sent as JSON
     */
    private boolean function isJsonPayload(required struct headers) {
        return headers['Content-Type'] == 'application/json';
    }

    /**
     * @hint helper to determine if body should be sent as form params
     */
    private boolean function isFormPayload(required struct headers) {
        return arrayContains(['application/x-www-form-urlencoded', 'multipart/form-data'], headers['Content-Type']);
    }

    /**
     *
     * Based on an (old) blog post and UDF from Raymond Camden
     * https://www.raymondcamden.com/2012/01/04/Converting-XML-to-JSON-My-exploration-into-madness/
     *
     */
    private struct function xmlToStruct(required any x) {
        if (isSimpleValue(x) && isXML(x)) {
            x = xmlParse(x);
        }

        var s = {};

        if (xmlGetNodeType(x) == 'DOCUMENT_NODE') {
            s[structKeyList(x)] = xmlToStruct(x[structKeyList(x)]);
        }

        if (structKeyExists(x, 'xmlAttributes') && !structIsEmpty(x.xmlAttributes)) {
            s.attributes = {};
            for (var item in x.xmlAttributes) {
                s.attributes[item] = x.xmlAttributes[item];
            }
        }

        if (structKeyExists(x, 'xmlText') && x.xmlText.trim().len()) {
            s.value = x.xmlText;
        }

        if (structKeyExists(x, 'xmlChildren')) {
            for (var xmlChild in x.xmlChildren) {
                if (structKeyExists(s, xmlChild.xmlname)) {
                    if (!isArray(s[xmlChild.xmlname])) {
                        var temp = s[xmlChild.xmlname];
                        s[xmlChild.xmlname] = [temp];
                    }

                    arrayAppend(s[xmlChild.xmlname], xmlToStruct(xmlChild));
                } else {
                    if (structKeyExists(xmlChild, 'xmlChildren') && arrayLen(xmlChild.xmlChildren)) {
                        s[xmlChild.xmlName] = xmlToStruct(xmlChild);
                    } else if (structKeyExists(xmlChild, 'xmlAttributes') && !structIsEmpty(xmlChild.xmlAttributes)) {
                        s[xmlChild.xmlName] = xmlToStruct(xmlChild);
                    } else {
                        s[xmlChild.xmlName] = xmlChild.xmlText;
                    }
                }
            }
        }

        return s;
    }

    public any function OnMissingMethod(required String MissingMethodName, required struct MissingMethodArguments) {
        var args = {};
        if (left(arguments.MissingMethodName, 3) == 'get' && right(arguments.MissingMethodName, 4) != 'ById') {
            args.module = mid(arguments.MissingMethodName, 4, len(arguments.MissingMethodName) - 3);
            args.append(arguments.MissingMethodArguments);
            return getRecords(argumentCollection = args);
        } else if (left(arguments.MissingMethodName, 3) == 'get' && right(arguments.MissingMethodName, 4) == 'ById') {
            args.module = mid(arguments.MissingMethodName, 4, len(arguments.MissingMethodName) - 7);
            args.append(arguments.MissingMethodArguments);
            return getRecordById(argumentCollection = args);
        } else if (left(arguments.MissingMethodName, 6) == 'insert') {
            args.module = mid(arguments.MissingMethodName, 7, len(arguments.MissingMethodName) - 3);
            if (!arguments.MissingMethodArguments.keyExists('records')) {
                args.records = arguments.MissingMethodArguments[1];
            }
            args.append(arguments.MissingMethodArguments);
            return insertRecords(argumentCollection = args);
        } else if (left(arguments.MissingMethodName, 6) == 'update' && right(arguments.MissingMethodName, 4) != 'ById') {
            args.module = mid(arguments.MissingMethodName, 7, len(arguments.MissingMethodName) - 6);
            if (arguments.MissingMethodArguments.keyExists('record')) {
                args.records = arguments.MissingMethodArguments.record;
            }
            if (arguments.MissingMethodArguments.keyExists('1')) {
                args.id = arguments.MissingMethodArguments.1;
            }
            if (arguments.MissingMethodArguments.keyExists('2')) {
                args.records = arguments.MissingMethodArguments.2;
            }
            args.append(arguments.MissingMethodArguments);
            return updateRecords(argumentCollection = args);
        } else if (left(arguments.MissingMethodName, 6) == 'delete' && right(arguments.MissingMethodName, 4) != 'ById') {
            args.module = mid(arguments.MissingMethodName, 7, len(arguments.MissingMethodName) - 6);
            if (!arguments.MissingMethodArguments.keyExists('ids')) {
                args['ids'] = arguments.MissingMethodArguments[1];
            }
            args.append(arguments.MissingMethodArguments);
            return deleteRecords(argumentCollection = args);
        } else if (left(arguments.MissingMethodName, 6) == 'delete' && right(arguments.MissingMethodName, 4) == 'ById') {
            args.module = mid(arguments.MissingMethodName, 7, len(arguments.MissingMethodName) - 10);
            if (!arguments.MissingMethodArguments.keyExists('ids')) {
                args['ids'] = arguments.MissingMethodArguments[1];
            }
            args.append(arguments.MissingMethodArguments);
            return deleteRecords(argumentCollection = args);
        } else {
            throw(message = 'Method not found', type = 'zohoCRM.methodNotFound');
        }
    }

}
