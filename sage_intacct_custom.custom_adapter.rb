{
  title: 'Sage Intacct (Custom)',

  methods: {
    convert_date: lambda do |input|
      input&.to_date&.strftime('%m/%d/%Y')
    end,
    ##############################################################
    # Helper methods                                             #
    ##############################################################
    # This method is for Custom action
    make_schema_builder_fields_sticky: lambda do |schema|
      schema.map do |field|
        if field['properties'].present?
          field['properties'] = call('make_schema_builder_fields_sticky',
                                     field['properties'])
        end
        field['sticky'] = true

        field
      end
    end,

    # Formats input/output schema to replace any special characters in name,
    # without changing other attributes (method required for custom action)
    format_schema: lambda do |input|
      input&.map do |field|
        if (props = field[:properties])
          field[:properties] = call('format_schema', props)
        elsif (props = field['properties'])
          field['properties'] = call('format_schema', props)
        end
        if (name = field[:name])
          field[:label] = field[:label].presence || name.labelize
          field[:name] = name.
                         gsub(/\W/) { |spl_chr| "__#{spl_chr.encode_hex}__" }
        elsif (name = field['name'])
          field['label'] = field['label'].presence || name.labelize
          field['name'] = name.
                          gsub(/\W/) { |spl_chr| "__#{spl_chr.encode_hex}__" }
        end

        field
      end
    end,

    # Formats payload to inject any special characters that previously removed
    format_payload: lambda do |payload|
      if payload.is_a?(Array)
        payload.map do |array_value|
          call('format_payload', array_value)
        end
      elsif payload.is_a?(Hash)
        payload.each_with_object({}) do |(key, value), hash|
          key = key.gsub(/__\w+__/) do |string|
            string.gsub(/__/, '').decode_hex.as_utf8
          end
          value = call('format_payload', value) if value.is_a?(Array) || value.is_a?(Hash)
          hash[key] = value
        end
      end
    end,

    # Formats response to replace any special characters with valid strings
    # (method required for custom action)
    format_response: lambda do |response|
      response = response&.compact unless response.is_a?(String) || response
      if response.is_a?(Array)
        response.map do |array_value|
          call('format_response', array_value)
        end
      elsif response.is_a?(Hash)
        response.each_with_object({}) do |(key, value), hash|
          key = key.gsub(/\W/) { |spl_chr| "__#{spl_chr.encode_hex}__" }
          value = call('format_response', value) if value.is_a?(Array) || value.is_a?(Hash)
          hash[key] = value
        end
      else
        response
      end
    end,

    format_input_to_match_schema: lambda do |arg|
      arg['schema'].each_with_object({}) do |schema_field, hash|
        field_name = (schema_field[:name] || schema_field['name'])&.to_s
        field_props = schema_field[:properties] || schema_field['properties']
        field_value = arg.dig('input', field_name) ||
                      arg.dig('input', field_name&.to_sym)
        next if field_value.nil?

        if field_props.blank?
          hash[field_name] = field_value
        elsif ['object', :object].include?(schema_field[:type] ||
                                           schema_field['type'])
          hash[field_name] =
            if field_value.is_a?(Hash)
              call('format_input_to_match_schema',
                   'schema' => field_props,
                   'input' => field_value)&.compact
            else
              field_value
            end
        elsif ['array', :array].include?(schema_field[:type] ||
                                         schema_field['type'])
          hash[field_name] =
            if field_value.is_a?(Array)
              field_value&.map do |element|
                call('format_input_to_match_schema',
                     'schema' => field_props,
                     'input' => element)
              end&.compact
            else
              field_value
            end
        end
      end
    end,

    parse_xml_to_hash: lambda do |xml_obj|
      xml_obj['xml']&.
        inject({}) do |hash, (key, value)|
        if value.is_a?(Array)
          hash.merge(if (array_fields = xml_obj['array_fields'])&.include?(key)
                       {
                         key => value.map do |inner_hash|
                                  call('parse_xml_to_hash',
                                       'xml' => inner_hash,
                                       'array_fields' => array_fields)
                                end
                       }
                     else
                       {
                         key => call('parse_xml_to_hash',
                                     'xml' => value[0],
                                     'array_fields' => array_fields)
                       }
                     end)
        elsif key == 'content!'
          value
        else
          { key => value }
        end
      end&.presence
    end,

    deep_compact: lambda do |input|
      input = input&.compact || input
      if input.is_a?(Array)
        input.compact.map do |array_value|
          call('deep_compact', array_value)
        end
      elsif input.is_a?(Hash)
        input.each_with_object({}) do |(key, value), hash|
          value = call('deep_compact', value) if value.is_a?(Array) || value.is_a?(Hash)
          hash[key] = value
        end.compact
      else
        input
      end
    end,

    # basic XML validation
    validate_xml_string: lambda do |xml_str|
      # xml_str.match(/<.[^(><.)]+>/) && xml_str.scan(/<.[^(><.)]+>/).length.even?
      xml_str.match(/<.[^(><.)]+>/)
    end,

    validate_intacct_xml_response_string: lambda do |xml_str|
      if xml_str.match(/<.[^(><.)]+>/)
        xml_tags = xml_str.scan(/<.[^(><.)]+>/)
        if xml_tags&.[](0) == '<response>' &&
           xml_tags&.[](-1) == '</response>'
          next true
        end
      end
      false
    end,

    render_date_input: lambda do |input|
      if input.is_a?(Array)
        input.map do |array_value|
          call('render_date_input', array_value)
        end
      elsif input.is_a?(Hash)
        input.map do |key, value|
          value = call('render_date_input', value)
          if (downcase_key = key.downcase).include?('date') ||
             %w[].include?(downcase_key) # add all date fields without having `date` in field name
            { key => value&.to_date&.strftime('%m/%d/%Y') }
          else
            { key => value }
          end
        end.inject(:merge)
      else
        input
      end
    end,

    add_required_attribute: lambda do |input|
      (object_def = input['object_def']).
        where(name: input['fields']).
        each do |field|
        field[:optional] = false
        # applying required attributes to toggle_field
        if (toggle_field = field[:toggle_field].presence)
          toggle_field[:optional] = false
        end
      end

      object_def
    end,

    get_custom_field_schema: lambda do |input|
      type_map = {
        'string' => 'string',
        'integer' => 'integer',
        'date' => 'date',
        'boolean' => 'boolean',
        'datetime' => 'date_time',
        'currency' => 'number',
        'number' => 'number'
      }
      control_type_map = {
        'boolean' => 'checkbox',
        'date_time' => 'date_time',
        'date' => 'date',
        'number' => 'number'
      }
      render_input_map = {
        'integer' => 'integer_conversion',
        'number' => 'float_conversion'
      }
      parse_output_map = {
        'integer' => 'integer_conversion',
        'number' => 'float_conversion'
      }

      # fields with id >= 1000 & id < 10000 are custom fields
      # custom-field <id>999502600001031</id>
      # custom-dimension field <id>10103</id>
      # custom-relationship <id>10105</id>
      custom_fields = input.select do |field|
        ((id_sbint = field['id'][/\d{6}$/].to_i) >= 1_000) &&
          (id_sbint < 10_000)
      end
      custom_fields.map do |field|
        data_type = type_map[field['externalDataName']]
        hint = unless (description = field['Description'])&.
                      casecmp(label = field['DisplayLabel']) == 0
                 description
               end

        {
          name: field['Name'],
          label: label,
          hint: hint,
          custom: true,
          sticky: true,
          render_input: render_input_map[data_type],
          parse_output: parse_output_map[data_type],
          control_type: control_type_map[data_type],
          type: data_type
        }.compact
      end
    end,

    get_custom_fields: lambda do |object|
      function = {
        '@controlid' => 'testControlId',
        'inspect' => { '@detail' => '1', 'object' => object }
      }
      response_data = call('get_api_response_data_element', function)

      call('format_schema',
           call('get_custom_field_schema',
                call('parse_xml_to_hash',
                     'xml' => response_data,
                     'array_fields' => ['Field'])&.
                  dig('Type', 'Fields', 'Field')))
    end,

    get_object_definition: lambda do |input|
      type_map = {
        'string' => 'string',
        'integer' => 'integer',
        'date' => 'date',
        'boolean' => 'boolean',
        'datetime' => 'date_time',
        'currency' => 'number',
        'number' => 'number'
      }
      control_type_map = {
        'boolean' => 'checkbox',
        'date_time' => 'date_time',
        'date' => 'date',
        'number' => 'number'
      }
      render_input_map = {
        'integer' => 'integer_conversion',
        'number' => 'float_conversion',
        # TODO: check, render_input is not working for date fields!
        'date' => ->(field) { field&.to_date&.strftime('%m/%d/%Y') },
        'date_time' => lambda do |field|
          field&.to_time&.utc&.strftime('%m/%d/%Y %H:%M:%S')
        end
      }
      parse_output_map = {
        'integer' => 'integer_conversion',
        'number' => 'float_conversion',
        'date' => ->(field) { field&.to_date(format: '%m/%d/%Y') },
        'date_time' => lambda do |field|
          field&.to_time(format: '%m/%d/%Y %H:%M:%S')
        end
      }

      input.map do |field|
        data_type = type_map[field['externalDataName']]
        hint = unless (description = field['Description'])&.
                      casecmp(label = field['DisplayLabel']) == 0
                 description
               end

        {
          name: (name = field['Name']),
          label: label,
          hint: hint,
          sticky: (name == 'NAME') || (name == 'RECORDNO') ||
            (name == 'DESCRIPTION'),
          render_input: render_input_map[data_type],
          parse_output: parse_output_map[data_type],
          control_type: control_type_map[data_type],
          type: data_type
        }.compact
      end
    end,

    get_task_object_definition: lambda do |input|
      type_map = {
        'string' => 'string',
        'integer' => 'integer',
        'date' => 'date',
        'boolean' => 'boolean',
        'datetime' => 'date_time',
        'currency' => 'number',
        'number' => 'number'
      }
      control_type_map = {
        'boolean' => 'checkbox',
        'date_time' => 'date_time',
        'date' => 'date',
        'number' => 'number'
      }
      render_input_map = {
        'integer' => 'integer_conversion',
        'number' => 'float_conversion',
        # TODO: check, render_input is not working for date fields!
        'date' => ->(field) { field&.to_date&.strftime('%Y-%m-%d') },
        'date_time' => lambda do |field|
          field&.to_time&.utc&.strftime('%Y-%m-%dT%H:%M:%SZ')
        end
      }
      parse_output_map = {
        'integer' => 'integer_conversion',
        'number' => 'float_conversion',
        'date' => ->(field) { field&.to_date(format: '%Y-%m-%d') },
        'date_time' => lambda do |field|
          field&.to_time(format: '%Y-%m-%dT%H:%M:%SZ')
        end
      }

      input.map do |field|
        data_type = type_map[field['externalDataName']]
        hint = unless (description = field['Description'])&.
                      casecmp(label = field['DisplayLabel']) == 0
                 description
               end

        {
          name: (name = field['Name']),
          label: label,
          hint: hint,
          sticky: (name == 'NAME') || (name == 'RECORDNO') ||
            (name == 'DESCRIPTION'),
          render_input: render_input_map[data_type],
          parse_output: parse_output_map[data_type],
          control_type: control_type_map[data_type],
          type: data_type
        }.compact
      end
    end,

    # Intacct API response validation
    validate_intacct_response_auth_error: lambda do |response|
      # <response><control><status>failure -> validation
      # <response><operation><authentication><status>failure -> validation
      response = response.dig('response', 0)
      if response&.dig('control', 0,
                       'status', 0, 'content!') != 'success' ||
         response&.dig('operation', 0,
                       'authentication', 0,
                       'status', 0,
                       'content!') != 'success'
        error((call('parse_xml_to_hash',
                    'xml' => response,
                    'array_fields' => %w[error]) || {})&.to_json)
      end

      response
    end,

    get_endpoint_url: lambda do |connection|
      connection['endpoint'] || 'https://api.intacct.com/ia/xml/xmlgw.phtml'
    end,

    get_api_response_result_element: lambda do |input|
      payload = {
        'control' => {},
        'operation' => {
          'authentication' => {},
          'content' => { 'function' => input }
        }
      }

      post('/ia/xml/xmlgw.phtml', payload).
        format_xml('request').
        after_error_response(/.*/) do |_code, body, _headers, message|
          error("{ \"error\": \"#{message}\", \"details\": \"#{body}\" }")
        end&.
        after_response do |_code, body, _headers|
          result = call('validate_intacct_response_auth_error', body)&.
                   dig('operation', 0, 'result', 0)
          if result&.dig('status', 0, 'content!') == 'failure'
            result_hash = call('parse_xml_to_hash',
                               'xml' => result,
                               'array_fields' => %w[result error]) || {}
            error(result_hash['errormessage']&.to_json)
          else
            result
          end
        end
    end,

    get_api_response_data_element: lambda do |input|
      call('get_api_response_result_element', input)&.dig('data', 0)
    end,

    get_api_response_operation_element: lambda do |input|
      payload = {
        'control' => {},
        'operation' => { 'authentication' => {}, 'content' => input }
      }

      post('/ia/xml/xmlgw.phtml', payload).
        format_xml('request').
        after_error_response(/.*/) do |_code, body, _headers, message|
          error("{ \"error\": \"#{message}\", \"details\": \"#{body}\" }")
        end&.
        after_response do |_code, body, _headers|
          call('validate_intacct_response_auth_error', body)&.
            dig('operation', 0)
        end
    end,

    get_api_response_element: lambda do |input|
      response =
        post(call('get_endpoint_url', input['connection']), input['payload']).
        format_xml('request').
        after_error_response(/.*/) do |_code, body, _headers, message|
          error("{ \"error\": \"#{message}\", \"details\": \"#{body}\" }")
        end

      response.after_response do |_code, res_body, _res_headers|
        call('parse_xml_to_hash',
             'xml' => call('validate_intacct_response_auth_error', res_body),
             'array_fields' => %w[result error]) || {}
      end
    end,

    batch_input_schema: lambda do |input|
      [
        {
          name: 'control_element',
          label: 'Control element of XML request',
          hint: 'Control element applies to the entire request. ' \
          "<a href='https://developer." \
          "intacct.com/web-services/requests/#control-element' " \
          "target='_blank'>Learn more</a>",
          type: 'object',
          properties: [
            {
              name: 'controlid',
              label: 'Control ID',
              hint: 'Control ID for request as a whole.'
            },
            {
              name: 'uniqueid',
              label: 'Unique ID',
              hint: 'Used in conjuction with "Control ID". Specifies ' \
              'whether a request can be submitted more than once without ' \
              'an error. When set to Yes, which is the default, a ' \
              'request cannot be repeated. The "Control ID" attribute of ' \
              'the <function> element will be checked to determine if ' \
              'the operation was previously executed and completed. When ' \
              'set to No, the system allows the operation to execute ' \
              'any number of times.',
              control_type: 'checkbox',
              type: 'boolean',
              toggle_hint: 'Select from list',
              toggle_field: {
                name: 'uniqueid',
                label: 'Unique ID',
                hint: 'Used in conjuction with "Control ID". Specifies ' \
                'whether a request can be submitted more than once without ' \
                'an error. When set to true, which is the default, a ' \
                'request cannot be repeated. The "Control ID" attribute of ' \
                'the <function> element will be checked to determine if ' \
                'the operation was previously executed and completed. When ' \
                'set to false, the system allows the operation to execute ' \
                'any number of times.',
                toggle_hint: 'Use custom value',
                optional: true,
                control_type: 'text',
                type: 'string'
              }
            }
          ]
        },
        {
          name: 'operation_element',
          label: 'Operation element of XML request',
          hint: 'Provides the content for the request.' \
          " <a href='https://developer." \
          "intacct.com/web-services/requests/#operation-element' " \
          "target='_blank'>Learn more</a>",
          optional: false,
          type: 'object',
          properties: [
            {
              name: 'transaction',
              label: 'Transaction',
              hint: 'Specifies whether all the functions in the ' \
              'operation block represent a single transaction. When set ' \
              'to Yes, all of the functions are treated as a single ' \
              'transaction. If one function fails, all previously ' \
              'executed functions within the operation are rolled back. ' \
              'This is useful for groups of functions that rely on each ' \
              'other to change information in the database. When set to ' \
              'No, which is the default, functions execute ' \
              'independently. If one function fails, others still proceed.',
              control_type: 'checkbox',
              type: 'boolean',
              toggle_hint: 'Select from list',
              toggle_field: {
                name: 'transaction',
                label: 'Transaction',
                hint: 'Specifies whether all the functions in the ' \
                'operation block represent a single transaction. When set ' \
                'to true, all of the functions are treated as a single ' \
                'transaction. If one function fails, all previously ' \
                'executed functions within the operation are rolled back. ' \
                'This is useful for groups of functions that rely on each ' \
                'other to change information in the database. When set to ' \
                'false, which is the default, functions execute ' \
                'independently. If one function fails, others still proceed.',
                toggle_hint: 'Use custom value',
                optional: true,
                control_type: 'text',
                type: 'string'
              }
            },
            {
              name: 'function',
              label: input['function_name'] || 'Batch of record',
              optional: false,
              type: 'array',
              of: 'object',
              properties: [
                {
                  name: '@controlid',
                  label: 'Control ID',
                  hint: 'Identifier for the contract line that can be used ' \
                  'to correlate the results from the response. To assure ' \
                  'transaction idempotence, use unique values such as ' \
                  "GUIDs or sequenced numbers. <a href='https://developer." \
                  "intacct.com/web-services/requests/#function-element' " \
                  "target='_blank'>Learn more</a>",
                  optional: false
                },
                input['function_data']
              ].compact
            }
          ]
        }
      ]
    end,

    batch_output_schema: lambda do |input|
      [
        {
          name: 'operation',
          type: 'object',
          properties: [{
            name: 'result',
            type: 'array',
            of: 'object',
            properties: [
              { name: 'status' },
              { name: 'function' },
              { name: 'controlid', label: 'Control ID' },
              {
                name: 'data',
                type: 'object',
                properties: input['data_prop']
              },
              {
                name: 'errormessage',
                label: 'Error message',
                type: 'object',
                properties: [{
                  name: 'error',
                  type: 'array',
                  of: 'object',
                  properties: [
                    { name: 'errorno', label: 'Error number' },
                    { name: 'description' },
                    { name: 'description2' },
                    { name: 'correction' }
                  ]
                }]
              }
            ]
          }]
        }
      ]
    end,

    # Object schemas
    ar_adjustment_create_schema: lambda do
      [
        { name: 'customerid', optional: false, label: 'Customer ID' },
        {
          name: 'datecreated',
          label: 'Date created',
          optional: false,
          hint: 'Transaction date. Required field',
          type: 'object',
          properties: [
            {
              name: 'year',
              hint: 'Year in yyyy format',
              control_type: 'integer',
              optional: false,
              type: 'integer'
            },
            {
              name: 'month',
              hint: 'Month in mm format',
              control_type: 'integer',
              optional: false,
              type: 'integer'
            },
            {
              name: 'day',
              hint: 'Day in dd format',
              control_type: 'integer',
              optional: false,
              type: 'integer'
            }
          ]
        },
        {
          name: 'dateposted',
          label: 'GL posting date',
          type: 'object',
          properties: [
            {
              name: 'year',
              control_type: 'integer',
              type: 'integer',
              hint: 'Year in yyyy format'
            },
            {
              name: 'month',
              control_type: 'integer',
              type: 'integer',
              hint: 'Month in mm format'
            },
            {
              name: 'day',
              control_type: 'integer',
              type: 'integer',
              hint: 'Day in dd format'
            }
          ]
        },
        { name: 'batchkey', type: 'integer' },
        { name: 'adjustmentno', label: 'Adjustment number' },
        { name: 'action', hint: 'Use Draft or Submit. (Default: Submit)' },
        { name: 'invoiceno', label: 'Invoice number' },
        { name: 'description', label: 'Description', sticky: true },
        { name: 'externalid', label: 'External ID' },
        {
          name: 'basecurr',
          label: 'Base currency code',
          hint: 'e.g. USD for US Dollars',
          sticky: true
        },
        {
          name: 'currency',
          label: 'Transaction currency code',
          hint: 'e.g. USD for US Dollars',
          sticky: true
        },
        {
          name: 'exchratedate',
          label: 'Exchange rate date',
          sticky: true,
          type: 'object',
          properties: [
            {
              name: 'year',
              control_type: 'integer',
              type: 'integer',
              hint: 'Year in yyyy format'
            },
            {
              name: 'month',
              control_type: 'integer',
              type: 'integer',
              hint: 'Month in mm format'
            },
            {
              name: 'day',
              control_type: 'integer',
              type: 'integer',
              hint: 'Day in dd format'
            }
          ]
        },
        {
          name: 'exchratetype',
          label: 'Exchange rate type',
          sticky: true,
          hint: 'Do not use if exchange rate is set. ' \
            '(Leave blank to use Intacct Daily Rate)'
        },
        {
          name: 'exchrate',
          label: 'Exchange rate',
          hint: 'Do not use if exchange rate type is set.'
        },
        {
          name: 'nogl',
          control_type: 'checkbox',
          label: 'Do not post to GL',
          hint: 'Use false for No, true for Yes. (Default: false)',
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'nogl',
            label: 'Do not post to GL',
            hint: 'Use false for No, true for Yes. (Default: false)',
            toggle_hint: 'Use custom value',
            optional: true,
            control_type: 'text',
            type: 'string'
          }
        },
        {
          name: 'taxsolutionid',
          label: 'Tax solution ID',
          hint: 'Tax solution name, such as <b>United Kingdom - VAT or ' \
          'Australia - GST</b>. Required only if the company is configured ' \
          'for multiple tax jurisdictions and the transaction is occurring ' \
          'at the top level of the company. The available tax solution names ' \
          'can be found in the Sage Intacct UI in the Taxes application ' \
          'from the top level of a multi-entity company. (GB, AU, and ZA only)'
        },
        {
          name: 'aradjustmentitems',
          label: 'AR adjustment items',
          hint: 'Invoice lines, must have at least 1',
          optional: false,
          type: 'array',
          of: 'object',
          properties: [{
            name: 'lineitem',
            label: 'Line item',
            optional: false,
            type: 'array',
            of: 'object',
            properties: [
              {
                name: 'glaccountno',
                label: 'GL account number',
                hint: 'Required if not using AR account label.',
                sticky: true
              },
              {
                name: 'accountlabel',
                label: 'AR account label',
                hint: 'Required if not using Gl account number',
                sticky: true
              },
              { name: 'offsetglaccountno', label: 'Offset GL account number' },
              {
                name: 'amount',
                label: 'Transaction amount',
                optional: false,
                type: 'number'
              },
              { name: 'memo' },
              { name: 'locationid', label: 'Location ID' },
              { name: 'departmentid', label: 'Department ID' },
              { name: 'key', sticky: true },
              {
                name: 'totalpaid',
                label: 'Total paid',
                hint: 'Used when </b>Do not post to GL</b> on bill is true'
              },
              {
                name: 'totaldue',
                label: 'Total due',
                hint: 'Used when </b>Do not post to GL</b> on bill is true'
              },
              {
                name: 'customfields',
                label: 'Custom fields/dimensions',
                sticky: true,
                type: 'array',
                of: 'object',
                properties: [{
                  name: 'customfield',
                  label: 'Custom field/dimension',
                  sticky: true,
                  type: 'array',
                  of: 'object',
                  properties: [
                    {
                      name: 'customfieldname',
                      label: 'Custom field/dimension name',
                      hint: 'Integration name of the custom field or ' \
                        'custom dimension. Find integration name in object ' \
                        'definition page of the respective object. Prepend ' \
                        "custom dimension with 'GLDIM'; e.g., if the " \
                        'custom dimension is Rating, use ' \
                        "'<b>GLDIM</b>Rating' as integration name here.",
                      sticky: true
                    },
                    {
                      name: 'customfieldvalue',
                      label: 'Custom field/dimension value',
                      hint: 'The value of custom field or custom dimension',
                      sticky: true
                    }
                  ]
                }]
              },
              { name: 'projectid', label: 'Project ID' },
              {
                name: 'taskid',
                label: 'Task ID',
                hint: 'Only available when the parent <b>Project ID</b> is ' \
                'also specified.'
              },
              {
                name: 'costtypeid',
                label: 'Cost type ID',
                hint: 'Only available when the parent <b>Project ID and ' \
                'Task ID </b> are specified.'
              },
              { name: 'customerid', label: 'Customer ID' },
              { name: 'vendorid', label: 'Vendor ID' },
              { name: 'employeeid', label: 'Employee ID' },
              { name: 'itemid', label: 'Item ID' },
              { name: 'classid', label: 'Class ID' },
              { name: 'contractid', label: 'Contract ID' },
              { name: 'warehouseid', label: 'Warehouse ID' },
              {
                name: 'taxentries',
                label: 'Tax entries',
                type: 'array',
                of: 'object',
                properties: [{
                  name: 'taxentry',
                  label: 'Tax entry',
                  type: 'array',
                  of: 'object',
                  properties: [
                    {
                      name: 'detailid',
                      hint: "Unique ID of a <a href='https://developer." \
                      "intacct.com/api/general-ledger/tax-details/' " \
                      "target='_blank'>tax detail</a> with the tax rate to use"
                    },
                    {
                      name: 'trx_tax',
                      label: 'Transaction tax',
                      type: 'number',
                      hint: 'Transaction tax, which is a manually calculated ' \
                      'value to override the calculated value for the tax. ' \
                      'The amount of the tax line is automatically included ' \
                      'in the amount due (TOTAL_DUE) for the invoice'
                    }
                  ]
                }]
              }
            ]
          }]
        }
      ]
    end,

    ar_payment_create_schema: lambda do
      [
        { name: 'customerid', optional: false, label: 'Customer ID' },
        {
          name: 'paymentamount',
          optional: false,
          type: 'number',
          label: 'Transaction amount'
        },
        {
          name: 'translatedamount',
          type: 'number',
          label: 'Base amount'
        },
        {
          name: 'batchkey',
          label: 'Batch key',
          hint: 'AR payment summary record number to add this payment to.',
          type: 'integer'
        },
        {
          name: 'bankaccountid',
          label: 'Bank account ID',
          hint: 'Required if not using Undeposited funds GL account or ' \
          'Batch key',
          sticky: true
        },
        {
          name: 'undepfundsacct',
          label: 'Undeposited funds GL account',
          hint: 'Required if not using bankaccountid or batchkey. You can ' \
          'record the deposit so that your books reflect the transfer of ' \
          'funds from your undeposited funds account to your bank account ' \
          'when you move the held payments.'
        },
        { name: 'refid', label: 'Reference number' },
        { name: 'overpaylocid', label: 'Overpayment location ID' },
        { name: 'overpaydeptid', label: 'Overpayment department ID' },
        {
          name: 'datereceived',
          label: 'Date received',
          sticky: true,
          hint: 'Received Payment Date. Required field',
          type: 'object',
          properties: [
            {
              name: 'year',
              control_type: 'integer',
              type: 'integer',
              hint: 'Year in yyyy format'
            },
            {
              name: 'month',
              control_type: 'integer',
              type: 'integer',
              hint: 'Month in mm format'
            },
            {
              name: 'day',
              control_type: 'integer',
              type: 'integer',
              hint: 'Day in dd format'
            }
          ]
        },
        {
          name: 'paymentmethod',
          label: 'Payment method',
          hint: 'Use <b>Printed Check</b>, <b>Cash</b>, <b>EFT</b>, ' \
          '<b>Credit Card</b>, <b>Online Charge Card</b>, or ' \
          '<b>Online ACH Debit</b>',
          sticky: true
        },
        {
          name: 'basecurr',
          label: 'Base currency code',
          hint: 'e.g. USD for US Dollars'
        },
        {
          name: 'currency',
          label: 'Transaction currency code',
          hint: 'e.g. USD for US Dollars'
        },
        {
          name: 'exchratedate',
          label: 'Exchange rate date',
          sticky: true,
          type: 'object',
          properties: [
            {
              name: 'year',
              control_type: 'integer',
              type: 'integer',
              hint: 'Year in yyyy format'
            },
            {
              name: 'month',
              control_type: 'integer',
              type: 'integer',
              hint: 'Month in mm format'
            },
            {
              name: 'day',
              control_type: 'integer',
              type: 'integer',
              hint: 'Day in dd format'
            }
          ]
        },
        {
          name: 'exchratetype',
          label: 'Exchange rate type',
          sticky: true,
          hint: 'Do not use if exchange rate is set. ' \
            '(Leave blank to use Intacct Daily Rate)'
        },
        {
          name: 'exchrate',
          label: 'Exchange rate',
          hint: 'Do not use if exchange rate type is set.'
        },
        { name: 'cctype', label: 'Credit card type' },
        { name: 'authcode', label: 'Authorization code to use' },
        {
          name: 'arpaymentitem',
          label: 'AR payment item',
          hint: 'Payment items',
          type: 'array',
          of: 'object',
          properties: [
            { name: 'invoicekey', type: 'number', label: 'Invoice key' },
            { name: 'amount', type: 'number', label: 'Transaction amount' }
            ## below are not on docs of Intacct
            # { name: 'glaccountno', sticky: true, label: 'GL account number',
            #   hint: 'Required if not using AR account label.' },
            # { name: 'accountlabel', sticky: true, label: 'AR account label',
            #   hint: 'Required if not using Gl account number' },
            # { name: 'offsetglaccountno', label: 'Offset GL account number' },
            # { name: 'amount', type: 'number', label: 'Transaction amount' },
            # { name: 'memo' },
            # { name: 'locationid' },
            # { name: 'departmentid' },
            # { name: 'key' },
            # { name: 'totalpaid', label: 'Total paid',
            #   hint: 'Used when </b>Do not post to GL</b> on bill is true' },
            # { name: 'totaldue', label: 'Total due',
            #   hint: 'Used when </b>Do not post to GL</b> on bill is true' },
            # { name: 'allocationid', label: 'Allocation ID' },
          ]
        },
        {
          name: 'onlinecardpayment',
          label: 'Online card payment',
          hint: 'Online card payment fields only used if paymentmethod ' \
          'is Online Charge Card',
          type: 'object',
          properties: [
            { name: 'cardnum', hint: 'Card number' },
            { name: 'expirydate', hint: 'Expiration date' },
            { name: 'cardtype', hint: 'Card type' },
            { name: 'securitycode', hint: 'Security code' },
            {
              name: 'usedefaultcard',
              label: 'Use default card',
              control_type: 'checkbox',
              type: 'boolean',
              toggle_hint: 'Select from list',
              toggle_field: {
                name: 'usedefaultcard',
                label: 'Use default card',
                hint: 'Allowed values are: true, false.',
                toggle_hint: 'Use custom value',
                control_type: 'text',
                optional: true,
                type: 'string'
              }
            }
          ]
        },
        {
          name: 'onlineachpayment',
          label: 'Online ACH payment',
          hint: 'Online card payment fields only used if paymentmethod ' \
          'is Online ACH Debit',
          type: 'object',
          properties: [
            { name: 'bankname', hint: 'Bank name' },
            { name: 'accounttype', hint: 'Account type' },
            { name: 'accountnumber', hint: 'Account number' },
            { name: 'routingnumber', hint: 'Routing number' },
            { name: 'accountholder', hint: 'Account holder' },
            {
              name: 'usedefaultcard',
              label: 'Use default card',
              control_type: 'checkbox',
              type: 'boolean',
              toggle_hint: 'Select from list',
              toggle_field: {
                name: 'usedefaultcard',
                label: 'Use default card',
                hint: 'Allowed values are: true, false.',
                toggle_hint: 'Use custom value',
                control_type: 'text',
                optional: true,
                type: 'string'
              }
            }
          ]
        }
      ]
    end,

    contract_upsert_schema: lambda do
      [
        {
          name: 'RECORDNO',
          label: 'Record number',
          sticky: true,
          type: 'integer'
        },
        { name: 'CONTRACTID', label: 'Contract ID', sticky: true },
        { name: 'CUSTOMERID', label: 'Customer ID', sticky: true },
        { name: 'NAME', label: 'Contract name', sticky: true },
        {
          name: 'STATE',
          label: 'State',
          hint: 'State in which to create the contract. Use Draft ' \
          'for a contract that will not yet post to ' \
          'the GL (Default: In progress).',
          control_type: 'select',
          pick_list: 'contract_states',
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'STATE',
            label: 'State',
            hint: 'State in which to create the contract. Use Draft for ' \
            'a contract that will not yet post to the GL (Default: ' \
            'In progress). Allowed values are: Draft, In progress.',
            toggle_hint: 'Use custom value',
            control_type: 'text',
            optional: true,
            type: 'string'
          }
        },
        { name: 'CONTRACTTYPE', label: 'Contract type' },
        {
          name: 'BILLTOCONTACTNAME',
          label: 'Bill to contact name',
          hint: "Leave blank to use customer's default."
        },
        { name: 'DESCRIPTION', label: 'Description' },
        {
          name: 'SHIPTOCONTACTNAME',
          label: 'Ship to contact name',
          hint: 'Leave blank to use customer’s default.'
        },
        {
          name: 'BEGINDATE',
          label: 'Start date',
          convert_input: 'convert_date',
          convert_output: 'convert_date',
          type: 'date'
        },
        {
          name: 'ENDDATE',
          label: 'End date',
          convert_input: 'convert_date',
          convert_output: 'convert_date',
          type: 'date'
        },
        {
          name: 'BILLINGFREQUENCY',
          label: 'Billing frequency',
          control_type: 'select',
          pick_list: 'billing_frequencies',
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'BILLINGFREQUENCY',
            label: 'Billing frequency',
            hint: 'Allowed values are: Monthly, Quarterly, Annually.',
            toggle_hint: 'Use custom value',
            control_type: 'text',
            optional: true,
            type: 'string'
          }
        },
        { name: 'TERMNAME', label: 'Payment term' },
        { name: 'PRCLIST', label: 'Billing price list' },
        { name: 'MEAPRCLIST', label: 'Fair value price list' },
        {
          name: 'ADVBILLBY',
          label: 'Bill in advance',
          hint: 'Number of months or days before the start date. ' \
          'Overrides bill in advance settings on the customer.',
          control_type: 'integer',
          type: 'integer'
        },
        {
          name: 'ADVBILLBYTYPE',
          label: 'Bill in advance time period',
          hint: 'Required if using bill in advance.',
          sticky: true,
          control_type: 'select',
          pick_list: 'adv_bill_by_types',
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'ADVBILLBYTYPE',
            label: 'Bill in advance time period',
            hint: 'Required if using bill in advance. ' \
            'Allowed values are: days, months.',
            toggle_hint: 'Use custom value',
            control_type: 'text',
            sticky: true,
            optional: true,
            type: 'string'
          }
        },
        {
          name: 'RENEWALADVBILLBY',
          label: 'Bill in advance for renewals',
          control_type: 'integer',
          type: 'integer'
        },
        {
          name: 'RENEWALADVBILLBYTYPE',
          label: 'Bill in advance time period for renewals',
          hint: 'Required if using bill in advance for renewals.',
          sticky: true,
          control_type: 'select',
          pick_list: 'adv_bill_by_types',
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'RENEWALADVBILLBYTYPE',
            label: 'Bill in advance time period for renewals',
            hint: 'Required if using bill in advance for renewals. ' \
            'Allowed values are: days, months.',
            toggle_hint: 'Use custom value',
            control_type: 'text',
            sticky: true,
            optional: true,
            type: 'string'
          }
        },
        { name: 'SUPDOCID', label: 'Attachment ID' },
        {
          name: 'LOCATIONID',
          label: 'Location',
          sticky: true,
          control_type: 'select',
          pick_list: 'locations',
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'LOCATIONID',
            label: 'Location ID',
            toggle_hint: 'Use custom value',
            control_type: 'text',
            optional: true,
            type: 'string'
          }
        },
        {
          name: 'DEPARTMENTID',
          label: 'Department',
          control_type: 'select',
          pick_list: 'departments',
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'DEPARTMENTID',
            label: 'Department ID',
            toggle_hint: 'Use custom value',
            control_type: 'text',
            optional: true,
            type: 'string'
          }
        },
        {
          name: 'PROJECTID',
          label: 'Project',
          control_type: 'select',
          pick_list: 'projects',
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'PROJECTID',
            label: 'Project ID',
            toggle_hint: 'Use custom value',
            control_type: 'text',
            optional: true,
            type: 'string'
          }
        },
        {
          name: 'VENDORID',
          label: 'Vendor',
          control_type: 'select',
          pick_list: 'vendors',
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'VENDORID',
            label: 'Vendor ID',
            toggle_hint: 'Use custom value',
            control_type: 'text',
            optional: true,
            type: 'string'
          }
        },
        {
          name: 'EMPLOYEEID',
          label: 'Employee',
          control_type: 'select',
          pick_list: 'employees',
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'EMPLOYEEID',
            label: 'Employee ID',
            toggle_hint: 'Use custom value',
            control_type: 'text',
            optional: true,
            type: 'string'
          }
        },
        {
          name: 'CLASSID',
          label: 'Class',
          control_type: 'select',
          pick_list: 'classes',
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'CLASSID',
            label: 'Class ID',
            toggle_hint: 'Use custom value',
            control_type: 'text',
            optional: true,
            type: 'string'
          }
        },
        { name: 'BASECURR', label: 'Base currency', sticky: true },
        { name: 'CURRENCY', label: 'Transaction currency', sticky: true },
        { name: 'EXCHRATETYPE', label: 'Exchange rate type', sticky: true },
        {
          name: 'RENEWAL',
          label: 'Renewal',
          control_type: 'checkbox',
          type: 'boolean',
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'RENEWAL',
            label: 'Renewal',
            hint: 'Allowed values are: true, false.',
            toggle_hint: 'Use custom value',
            control_type: 'text',
            optional: true,
            type: 'string'
          }
        },
        {
          name: 'RENEWALMACRO',
          label: 'Renewal template',
          hint: 'Only used if Renewal is set'
        },
        {
          name: 'RENEWTERMLENGTH',
          label: 'Term length',
          hint: 'Only used if Renewal is set',
          control_type: 'integer',
          type: 'integer'
        },
        {
          name: 'RENEWTERMPERIOD',
          label: 'Renewal term period',
          hint: 'Only used if Renewal is set',
          control_type: 'select',
          pick_list: 'renewal_term_periods',
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'RENEWTERMPERIOD',
            label: 'Renewal term period',
            hint: 'Only used if Renewal is set. ' \
            'Allowed values are: Years, Months, Days.',
            toggle_hint: 'Use custom value',
            control_type: 'text',
            optional: true,
            type: 'string'
          }
        },
        {
          name: 'customfields',
          label: 'Custom fields/dimensions',
          sticky: true,
          type: 'array',
          of: 'object',
          properties: [{
            name: 'customfield',
            label: 'Custom field/dimension',
            sticky: true,
            type: 'array',
            of: 'object',
            properties: [
              {
                name: 'customfieldname',
                label: 'Custom field/dimension name',
                hint: 'Integration name of the custom field or ' \
                  'custom dimension. Find integration name in object ' \
                  'definition page of the respective object. Prepend ' \
                  "custom dimension with 'GLDIM'; e.g., if the " \
                  'custom dimension is Rating, use ' \
                  "'<b>GLDIM</b>Rating' as integration name here.",
                sticky: true
              },
              {
                name: 'customfieldvalue',
                label: 'Custom field/dimension value',
                hint: 'The value of custom field or custom dimension',
                sticky: true
              }
            ]
          }]
        }
      ]
    end,

    contract_line_upsert_schema: lambda do
      [
        {
          name: 'RECORDNO',
          label: 'Record number',
          sticky: true,
          type: 'integer'
        },
        { name: 'CONTRACTID', label: 'Contract ID', sticky: true },
        {
          name: 'ITEMID',
          label: 'Item',
          control_type: 'select',
          pick_list: 'items',
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'ITEMID',
            label: 'Item ID',
            toggle_hint: 'Use custom value',
            control_type: 'text',
            optional: true,
            type: 'string'
          }
        },
        {
          name: 'STATE',
          label: 'State',
          hint: 'State in which to create the contract line. Use Draft ' \
          'for a contract line that will not yet post to ' \
          'the GL (Default: In progress).',
          control_type: 'select',
          pick_list: 'contract_states',
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'STATE',
            label: 'State',
            hint: 'State in which to create the contract line. Use Draft for ' \
            'a contract line that will not yet post to the GL (Default: ' \
            'In progress). Allowed values are: Draft, In progress.',
            toggle_hint: 'Use custom value',
            control_type: 'text',
            optional: true,
            type: 'string'
          }
        },
        {
          name: 'BEGINDATE',
          label: 'Start date',
          hint: "Leave blank to use contract's",
          convert_input: 'convert_date',
          convert_output: 'convert_date',
          type: 'date'
        },
        {
          name: 'ENDDATE',
          label: 'End date',
          hint: "Leave blank to use contract's",
          convert_input: 'convert_date',
          convert_output: 'convert_date',
          type: 'date'
        },
        { name: 'ITEMDESC', label: 'Item description' },
        {
          name: 'RENEWAL',
          label: 'Renewal',
          control_type: 'checkbox',
          type: 'boolean',
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'RENEWAL',
            label: 'Renewal',
            hint: 'Allowed values are: true, false.',
            toggle_hint: 'Use custom value',
            control_type: 'text',
            optional: true,
            type: 'string'
          }
        },
        {
          name: 'EXCH_RATE_DATE',
          label: 'Exchange rate date',
          hint: 'Leave blank to use the start date (if the start is in ' \
          'the future, today’s date is used instead)',
          convert_input: 'convert_date',
          convert_output: 'convert_date',
          type: 'date'
        },
        {
          name: 'EXCHANGE_RATE',
          label: 'Exchange rate value',
          control_type: 'number',
          type: 'number'
        },
        {
          name: 'BILLINGMETHOD',
          label: 'Billing method',
          hint: 'Default: Fixed price',
          control_type: 'select',
          pick_list: 'billing_methods',
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'BILLINGMETHOD',
            label: 'Billing method',
            hint: 'Allowed values are: Fixed price, Quantity based.',
            toggle_hint: 'Use custom value',
            control_type: 'text',
            optional: true,
            type: 'string'
          }
        },
        {
          name: 'BILLINGOPTIONS',
          label: 'Flat/fixed amount frequency',
          control_type: 'select',
          pick_list: 'billing_options',
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'BILLINGOPTIONS',
            label: 'Flat/fixed amount frequency',
            hint: 'Allowed values are: One-time, Use billing template, ' \
            'Include with every invoice.',
            toggle_hint: 'Use custom value',
            control_type: 'text',
            optional: true,
            type: 'string'
          }
        },
        {
          name: 'BILLINGFREQUENCY',
          label: 'Billing frequency',
          hint: 'Billing frequency is required if <b>Flat/fixed amount ' \
          'frequency</b> is set to Include with every invoice',
          control_type: 'select',
          pick_list: 'billing_frequencies',
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'BILLINGFREQUENCY',
            label: 'Billing frequency',
            hint: 'Billing frequency is required if <b>Flat/fixed amount ' \
            'frequency</b> is set to Include with every invoice. ' \
            'Allowed values are: Monthly, Quarterly, Anually.',
            toggle_hint: 'Use custom value',
            control_type: 'text',
            optional: true,
            type: 'string'
          }
        },
        {
          name: 'PRORATEBILLINGPERIOD',
          label: 'Prorate billing period',
          hint: 'Specifies whether to prorate partial months. ' \
          'Use Yes to prorate, No otherwise. The <b>Billing method</b> must ' \
          'be set to Fixed price and <b>Flat/fixed amount frequency</b> must ' \
          'be set to Include with every invoice. (Default: No)',
          control_type: 'checkbox',
          type: 'boolean',
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'PRORATEBILLINGPERIOD',
            label: 'Prorate billing period',
            hint: 'Specifies whether to prorate partial months. ' \
            'Allowed values are: true, false. Use true to prorate, ' \
            'false otherwise. The <b>Billing method</b> must be set to Fixed ' \
            'price and <b>Flat/fixed amount frequency</b> must be set to ' \
            'Include with every invoice. (Default: false)',
            toggle_hint: 'Use custom value',
            control_type: 'text',
            optional: true,
            type: 'string'
          }
        },
        {
          name: 'BILLINGTEMPLATENAME',
          label: 'Billing template',
          hint: 'Only used if <b>Flat/fixed amount frequency</b> is Use ' \
          'billing template'
        },
        {
          name: 'BILLINGSTARTDATE',
          label: 'Billing start date',
          hint: 'Only used if <b>Flat/fixed amount frequency</b> is Use ' \
          'billing template. Leave blank to use line start date',
          convert_input: 'convert_date',
          convert_output: 'convert_date',
          type: 'date'
        },
        {
          name: 'BILLINGENDDATE',
          label: 'Billing end date',
          hint: 'Only used if <b>Flat/fixed amount frequency</b> is Use ' \
          'billing template. Leave blank to use line end date',
          convert_input: 'convert_date',
          convert_output: 'convert_date',
          type: 'date'
        },
        {
          name: 'USAGEQTYRESETPERIOD',
          label: 'Reset usage quantity',
          hint: 'Determines when the included units are counted and ' \
          'determines when the system billing counter resets. Only ' \
          'applicable if <b>Billing method</b> is set to Quantity based. ' \
          'Also, the contract must have a billing price list set (via PRCLIST)',
          control_type: 'select',
          pick_list: 'usage_quantity_resets',
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'USAGEQTYRESETPERIOD',
            label: 'Reset usage quantity',
            hint: 'Determines when the included units are counted and ' \
            'determines when the system billing counter resets. Only ' \
            'applicable if <b>Billing method</b> is set to Quantity based. ' \
            'Also, the contract must have a billing price list set ' \
            '(via PRCLIST). Allowed values are: ' \
            'After each invoice, After each renewal.',
            toggle_hint: 'Use custom value',
            control_type: 'text',
            optional: true,
            type: 'string'
          }
        },
        {
          name: 'USAGEQTYRECUR',
          label: 'Usage quantity recurs',
          hint: 'Determines when the included units are counted and ' \
          'determines when the system billing counter resets. Only ' \
          'applicable if <b>Billing method</b> is set to Quantity based. ' \
          'Also, the contract must have a billing price list set (via PRCLIST)',
          control_type: 'checkbox',
          type: 'boolean',
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'USAGEQTYRECUR',
            label: 'Usage quantity recurs',
            hint: 'Determines when the included units are counted and ' \
            'determines when the system billing counter resets. Only ' \
            'applicable if <b>Billing method</b> is set to Quantity based. ' \
            'Also, the contract must have a billing price list set ' \
            '(via PRCLIST). Allowed values are: true, false.',
            toggle_hint: 'Use custom value',
            control_type: 'text',
            optional: true,
            type: 'string'
          }
        },
        {
          name: 'RENEWALBILLINGTEMPLATENAME',
          label: 'Name of a renewal billing template',
          hint: 'Ensure the renewal billing template term is less than or ' \
          'equal to the contract renewal term. Only used if <b>Renewal</b> ' \
          'is true. If <b>Flat/fixed amount frequency</b> is set to Use ' \
          'billing template on the contract line, a billing template is ' \
          'required. If <b>Name of a renewal billing template</b> is ' \
          'omitted, the system first defaults to the <b>Billing template</b> ' \
          'on the contract line, then to the default billing template ' \
          'defined on the item'
        },
        {
          name: 'GLPOSTINGDATE',
          label: 'Date the Unbilled AR and Unbilled deferred revenue posts',
          hint: 'Leave blank to use the contract line start date minus the ' \
          'bill-in-advance period (if this would occur in a closed period, ' \
          'the first date in the first available open period is used ' \
          'instead)',
          convert_input: 'convert_date',
          convert_output: 'convert_date',
          type: 'date'
        },
        {
          name: 'QUANTITY',
          label: 'Flat/fixed amount calculate quantity',
          hint: 'Only used if <b>Billing method</b> is Fixed price',
          control_type: 'number',
          type: 'number'
        },
        {
          name: 'PRICE',
          label: 'Flat/fixed amount calculate rate',
          hint: 'Only used if <b>Billing method</b> is Fixed price',
          control_type: 'number',
          type: 'number'
        },
        {
          name: 'MULTIPLIER',
          label: 'Flat/fixed amount calculate multiplier',
          hint: 'Only used if <b>Billing method</b> is Fixed price',
          control_type: 'number',
          type: 'number'
        },
        {
          name: 'DISCOUNTPERCENT',
          label: 'Flat/fixed amount calculate discount',
          hint: 'Only used if <b>Billing method</b> is Fixed price',
          control_type: 'number',
          type: 'number'
        },
        {
          name: 'FLATAMOUNT',
          label: 'Base/flat fixed amount',
          control_type: 'number',
          type: 'number'
        },
        { name: 'REVENUETEMPLATENAME', label: '606 revenue template' },
        {
          name: 'REVENUESTARTDATE',
          label: '606 revenue start date',
          hint: 'Leave blank to use line start date',
          convert_input: 'convert_date',
          convert_output: 'convert_date',
          type: 'date'
        },
        {
          name: 'REVENUEENDDATE',
          label: '606 revenue end date',
          hint: 'Leave blank to use line end date',
          convert_input: 'convert_date',
          convert_output: 'convert_date',
          type: 'date'
        },
        { name: 'REVENUE2TEMPLATENAME', label: 'Legacy revenue template' },
        {
          name: 'REVENUE2STARTDATE',
          label: 'Legacy revenue start date',
          hint: 'Leave blank to use line start date',
          convert_input: 'convert_date',
          convert_output: 'convert_date',
          type: 'date'
        },
        {
          name: 'REVENUE2ENDDATE',
          label: 'Legacy revenue end date',
          hint: 'Leave blank to use line end date',
          convert_input: 'convert_date',
          convert_output: 'convert_date',
          type: 'date'
        },
        {
          name: 'SHIPTOCONTACTNAME',
          label: 'Ship to contact name',
          hint: 'Ship to contact name for the detail, which can override ' \
          'the Ship to contact name on the contract depending on the ' \
          'value of the Ship to source'
        },
        {
          name: 'SHIPTOSOURCE',
          label: 'Ship to source',
          hint: 'Specifies whether the Ship to contact name on the line ' \
          'is overridden when the Ship to contact name on the contract ' \
          'itself is modified. Use Contract value to allow this overriding ' \
          'or User-specified value to preserve the Ship to contact name on ' \
          'the line. (Default: If <b>Ship to contact name</b> is set and not ' \
          'equal to the contract Ship to, defaults to User-specified value, ' \
          'otherwise, defaults to Contract value)'
        },
        {
          name: 'LOCATIONID',
          label: 'Location',
          sticky: true,
          control_type: 'select',
          pick_list: 'locations',
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'LOCATIONID',
            label: 'Location ID',
            toggle_hint: 'Use custom value',
            control_type: 'text',
            optional: true,
            type: 'string'
          }
        },
        {
          name: 'DEPARTMENTID',
          label: 'Department',
          control_type: 'select',
          pick_list: 'departments',
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'DEPARTMENTID',
            label: 'Department ID',
            toggle_hint: 'Use custom value',
            control_type: 'text',
            optional: true,
            type: 'string'
          }
        },
        {
          name: 'PROJECTID',
          label: 'Project',
          control_type: 'select',
          pick_list: 'projects',
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'PROJECTID',
            label: 'Project ID',
            toggle_hint: 'Use custom value',
            control_type: 'text',
            optional: true,
            type: 'string'
          }
        },
        { name: 'TASKID', label: 'Task ID' },
        {
          name: 'VENDORID',
          label: 'Vendor',
          control_type: 'select',
          pick_list: 'vendors',
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'VENDORID',
            label: 'Vendor ID',
            toggle_hint: 'Use custom value',
            control_type: 'text',
            optional: true,
            type: 'string'
          }
        },
        {
          name: 'EMPLOYEEID',
          label: 'Employee',
          control_type: 'select',
          pick_list: 'employees',
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'EMPLOYEEID',
            label: 'Employee ID',
            toggle_hint: 'Use custom value',
            control_type: 'text',
            optional: true,
            type: 'string'
          }
        },
        {
          name: 'CLASSID',
          label: 'Class',
          control_type: 'select',
          pick_list: 'classes',
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'CLASSID',
            label: 'Class ID',
            toggle_hint: 'Use custom value',
            control_type: 'text',
            optional: true,
            type: 'string'
          }
        },
        {
          name: 'customfields',
          label: 'Custom fields/dimensions',
          sticky: true,
          type: 'array',
          of: 'object',
          properties: [{
            name: 'customfield',
            label: 'Custom field/dimension',
            sticky: true,
            type: 'array',
            of: 'object',
            properties: [
              {
                name: 'customfieldname',
                label: 'Custom field/dimension name',
                hint: 'Integration name of the custom field or ' \
                  'custom dimension. Find integration name in object ' \
                  'definition page of the respective object. Prepend ' \
                  "custom dimension with 'GLDIM'; e.g., if the " \
                  'custom dimension is Rating, use ' \
                  "'<b>GLDIM</b>Rating' as integration name here.",
                sticky: true
              },
              {
                name: 'customfieldvalue',
                label: 'Custom field/dimension value',
                hint: 'The value of custom field or custom dimension',
                sticky: true
              }
            ]
          }]
        }
      ]
    end,

    customer_create_schema: lambda do
      [
        {
          name: 'CUSTOMERID',
          label: 'Customer ID to create',
          hint: 'Required if company does not use auto-numbering',
          sticky: true
        },
        { name: 'NAME', label: 'Name', optional: false },
        {
          name: 'DISPLAYCONTACT',
          label: 'Contact info',
          type: 'object',
          properties: [
            { name: 'PRINTAS', label: 'Print as', optional: false },
            {
              name: 'CONTACTNAME',
              label: 'Contact name',
              hint: 'If left blank, system will create the name as ' \
              '[NAME](C[CUSTOMERID])',
              sticky: true
            },
            { name: 'COMPANYNAME', label: 'Company name' },
            {
              name: 'TAXABLE',
              label: 'Taxable',
              control_type: 'checkbox',
              type: 'boolean',
              toggle_hint: 'Select from list',
              toggle_field: {
                name: 'TAXABLE',
                label: 'Taxable',
                hint: 'Allowed values are: true, false (Default: true).',
                toggle_hint: 'Use custom value',
                control_type: 'text',
                optional: true,
                type: 'string'
              }
            },
            { name: 'TAXGROUP', label: 'Contact tax group name' },
            { name: 'PREFIX', label: 'Prefix' },
            { name: 'FIRSTNAME', label: 'First name' },
            { name: 'LASTNAME', label: 'Last name' },
            { name: 'INITIAL', label: 'Middle name' },
            {
              name: 'PHONE1',
              label: 'Primary phone number',
              control_type: 'phone'
            },
            {
              name: 'PHONE2',
              label: 'Secondary phone number',
              control_type: 'phone'
            },
            {
              name: 'CELLPHONE',
              label: 'Cellular phone number',
              control_type: 'phone'
            },
            { name: 'PAGER', label: 'Pager number' },
            { name: 'FAX', label: 'Fax number' },
            {
              name: 'EMAIL1',
              label: 'Primary email address',
              control_type: 'email'
            },
            {
              name: 'EMAIL2',
              label: 'Secondary email address',
              control_type: 'email'
            },
            { name: 'URL1', label: 'Primary URL', control_type: 'url' },
            { name: 'URL2', label: 'Secondary URL', control_type: 'url' },
            {
              name: 'MAILADDRESS',
              label: 'Mail address',
              type: 'object',
              properties: [
                { name: 'ADDRESS1', label: 'Address line 1' },
                { name: 'ADDRESS2', label: 'Address line 2' },
                { name: 'CITY', label: 'City' },
                { name: 'STATE', label: 'State/province' },
                { name: 'ZIP', label: 'Zip/postal code' },
                { name: 'COUNTRY', label: 'Country' },
                {
                  name: 'ISOCOUNTRYCODE',
                  label: 'ISO country code',
                  hint: 'When ISO country codes are enabled in a company, ' \
                  'both Country and ISO country code must be provided'
                }
              ]
            }
          ]
        },
        {
          name: 'STATUS',
          label: 'Status',
          hint: 'Default: Active',
          control_type: 'select',
          pick_list: 'statuses',
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'STATUS',
            label: 'Status',
            hint: 'Allowed values are: active, inactive',
            toggle_hint: 'Use custom value',
            control_type: 'text',
            optional: true,
            type: 'string'
          }
        },
        {
          name: 'ONETIME',
          label: 'One time',
          control_type: 'checkbox',
          type: 'boolean',
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'ONETIME',
            label: 'One time',
            hint: 'Allowed values are: true, false.',
            toggle_hint: 'Use custom value',
            control_type: 'text',
            optional: true,
            type: 'string'
          }
        },
        {
          name: 'HIDEDISPLAYCONTACT',
          label: 'Exclude from contact list',
          control_type: 'checkbox',
          type: 'boolean',
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'HIDEDISPLAYCONTACT',
            label: 'Exclude from contact list',
            hint: 'Allowed values are: true, false (Default: false).',
            toggle_hint: 'Use custom value',
            control_type: 'text',
            optional: true,
            type: 'string'
          }
        },
        { name: 'CUSTTYPE', label: 'Customer type ID' },
        { name: 'CUSTREPID', label: 'Sales rep employee ID' },
        { name: 'PARENTID', label: 'Parent customer ID' },
        { name: 'GLGROUP', label: 'GL group name' },
        { name: 'TERRITORYID', label: 'Territory ID' },
        { name: 'SUPDOCID', label: 'Attachments ID' },
        { name: 'TERMNAME', label: 'Payment term' },
        { name: 'OFFSETGLACCOUNTNO', label: 'Offset AR GL account number' },
        { name: 'ARACCOUNT', label: 'Default AR GL account number' },
        { name: 'SHIPPINGMETHOD', label: 'Shipping method' },
        { name: 'RESALENO', label: 'Resale number' },
        { name: 'TAXID', label: 'Tax ID' },
        { name: 'CREDITLIMIT', label: 'Credit limit' },
        {
          name: 'RETAINAGEPERCENTAGE',
          label: 'Default retainage percentage for customers',
          hint: '(Construction subscription)'
        },
        {
          name: 'ONHOLD',
          label: 'On hold',
          control_type: 'checkbox',
          type: 'boolean',
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'ONHOLD',
            label: 'On hold',
            hint: 'Allowed values are: true, false (Default: false).',
            toggle_hint: 'Use custom value',
            control_type: 'text',
            optional: true,
            type: 'string'
          }
        },
        {
          name: 'DELIVERY_OPTIONS',
          label: 'Delivery method',
          hint: 'Use either Print, E-Mail, or Print#~#E-Mail for both. If ' \
          'using E-Mail, the customer contact must have a valid e-mail address'
        },
        { name: 'CUSTMESSAGEID', label: 'Default invoice message' },
        {
          name: 'EMAILOPTIN',
          label: 'Accept emailed invoices option',
          control_type: 'checkbox',
          type: 'boolean',
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'EMAILOPTIN',
            label: 'Accept emailed invoices option',
            hint: 'Allowed values are: true, false. Applicable only for ' \
            'companies configured for South Africa (ZA) VAT',
            toggle_hint: 'Use custom value',
            control_type: 'text',
            optional: true,
            type: 'string'
          }
        },
        { name: 'COMMENTS', label: 'Comments' },
        { name: 'CURRENCY', label: 'Default currency code' },
        {
          name: 'ADVBILLBY',
          label: 'Bill in advance',
          hint: 'Number of months or days before the start date. ' \
          'Use 0 through 9',
          control_type: 'integer',
          type: 'integer'
        },
        {
          name: 'ADVBILLBYTYPE',
          label: 'Bill-in-advance time period',
          hint: 'Required if using bill in advance. Use days or months'
        },
        {
          name: 'ARINVOICEPRINTTEMPLATEID',
          label: 'Print option - AR invoice template name'
        },
        {
          name: 'OEQUOTEPRINTTEMPLATEID',
          label: 'Print option - OE quote template name'
        },
        {
          name: 'OEORDERPRINTTEMPLATEID',
          label: 'Print option - OE order template name'
        },
        {
          name: 'OELISTPRINTTEMPLATEID',
          label: 'Print option - OE list template name'
        },
        {
          name: 'OEINVOICEPRINTTEMPLATEID',
          label: 'Print option - OE invoice template name'
        },
        {
          name: 'OEADJPRINTTEMPLATEID',
          label: 'Print option - OE adjustment template name'
        },
        {
          name: 'OEOTHERPRINTTEMPLATEID',
          label: 'Print option - OE other template name'
        },
        {
          name: 'CONTACTINFO',
          label: 'Primary contact',
          hint: 'If blank system will use Display contact',
          type: 'object',
          properties: [{ name: 'CONTACTNAME', label: 'Contact name' }]
        },
        {
          name: 'BILLTO',
          label: 'Bill to contact',
          hint: 'If blank system will use Display contact',
          type: 'object',
          properties: [{ name: 'CONTACTNAME', label: 'Contact name' }]
        },
        {
          name: 'SHIPTO',
          label: 'Ship to contact',
          hint: 'If blank system will use Display contact',
          type: 'object',
          properties: [{ name: 'CONTACTNAME', label: 'Contact name' }]
        },
        {
          name: 'CONTACT_LIST_INFO',
          label: 'Contact list',
          hint: 'Multiple Contact list elements may then be passed',
          type: 'array',
          of: 'object',
          properties: [
            { name: 'CATEGORYNAME', label: 'Category' },
            {
              name: 'CONTACT',
              label: 'Contact',
              type: 'object',
              properties: [{ name: 'NAME', label: 'Contact name' }]
            }
          ]
        },
        {
          name: 'OBJECTRESTRICTION',
          label: 'Restriction type',
          hint: 'Use Unrestricted, RootOnly, or Restricted. ' \
          '(Default Unrestricted)'
        },
        {
          name: 'RESTRICTEDLOCATIONS',
          label: 'Restricted location ID’s',
          hint: 'Use if Restriction type is Restricted. ' \
          'Implode multiple ID’s with #~#'
        },
        {
          name: 'RESTRICTEDDEPARTMENTS',
          label: 'Restricted department ID’s',
          hint: 'Use if Restriction type is Restricted. ' \
          'Implode multiple ID’s with #~#'
        },
        {
          name: 'CUSTOMEREMAILTEMPLATES',
          label: 'Custom email templates',
          hint: 'Custom email templates to override the default email ' \
          'templates associated with transaction definitions. You choose ' \
          'existing custom email templates to use for this customer, ' \
          'optionally specifying the transactions to which they apply.',
          type: 'array',
          of: 'object',
          properties: [
            {
              name: 'CUSTOMEREMAILTEMPLATE',
              label: 'Customer email template',
              type: 'array',
              of: 'object',
              properties: [
                {
                  name: 'DOCPARID',
                  label: 'DOCPAR ID',
                  hint: 'Transaction definition that will use this email ' \
                  'template. Applicable only for Order Entry, Purchasing, ' \
                  'and Contract email templates'
                },
                {
                  name: 'EMAILTEMPLATENAME',
                  label: 'Name of the email template'
                }
              ]
            }
          ]
        },
        {
          name: 'customfields',
          label: 'Custom fields/dimensions',
          sticky: true,
          type: 'array',
          of: 'object',
          properties: [{
            name: 'customfield',
            label: 'Custom field/dimension',
            sticky: true,
            type: 'array',
            of: 'object',
            properties: [
              {
                name: 'customfieldname',
                label: 'Custom field/dimension name',
                hint: 'Integration name of the custom field or ' \
                  'custom dimension. Find integration name in object ' \
                  'definition page of the respective object. Prepend ' \
                  "custom dimension with 'GLDIM'; e.g., if the " \
                  'custom dimension is Rating, use ' \
                  "'<b>GLDIM</b>Rating' as integration name here.",
                sticky: true
              },
              {
                name: 'customfieldvalue',
                label: 'Custom field/dimension value',
                hint: 'The value of custom field or custom dimension',
                sticky: true
              }
            ]
          }]
        }
      ]
    end,

    contract_line_create_schema: lambda do
      contract_line_schema = call('contract_line_upsert_schema').
                             ignored('RECORDNO')

      call('add_required_attribute',
           'object_def' => contract_line_schema,
           'fields' => %w[CONTRACTID ITEMID BILLINGMETHOD LOCATIONID])
    end,

    contract_line_hold_schema: lambda do
      [
        { name: 'RECORDNO',
          label: 'Record number',
          optional: false,
          type: 'integer' },
        { name: 'ASOFDATE',
          label: 'Date to hold contract line',
          hint: 'Use the last posted schedule entry date + 1, ' \
                'if unsure of when to hold the contract line.',
          convert_input: 'convert_date',
          convert_output: 'convert_date',
          type: 'date',
          optional: false },
        { name: 'BILLING',
          label: 'Hold billing',
          control_type: 'checkbox',
          type: 'boolean',
          sticky: true,
          default: false,
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'BILLING',
            label: 'Hold billing',
            hint: 'Allowed values are: true, false.',
            toggle_hint: 'Use custom value',
            control_type: 'text',
            optional: true,
            sticky: true,
            type: 'string'
          } },
        { name: 'REVENUE',
          label: 'Hold revenue',
          control_type: 'checkbox',
          type: 'boolean',
          sticky: true,
          default: false,
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'REVENUE',
            label: 'Hold revenue',
            hint: 'Allowed values are: true, false.',
            toggle_hint: 'Use custom value',
            control_type: 'text',
            optional: true,
            sticky: true,
            type: 'string'
          } },
        { name: 'EXPENSE',
          label: 'Hold expense',
          control_type: 'checkbox',
          type: 'boolean',
          sticky: true,
          default: false,
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'EXPENSE',
            label: 'Hold expense',
            hint: 'Allowed values are: true, false.',
            toggle_hint: 'Use custom value',
            control_type: 'text',
            optional: true,
            sticky: true,
            type: 'string'
          } },
        { name: 'MEMO', label: 'Memo', sticky: true,
          hint: 'The description of the hold. Maximum limit of 500 characters.' }
      ]
    end,

    gl_batch_create_schema: lambda do
      [
        {
          name: 'JOURNAL',
          label: 'Journal',
          hint: 'GL journal symbol. This determines the type of journal ' \
          'entry as visible in the UI, for example, Regular, Adjustment, ' \
          'User-defined, Statistical, GAAP, Tax, and so forth.'
        },
        {
          name: 'RECORDNO',
          label: 'Record number',
          hint: "Journal entry 'Record number' to update",
          sticky: true,
          type: 'integer'
        },
        {
          name: 'BATCH_DATE',
          label: 'Batch date',
          hint: 'Posting date',
          sticky: true,
          convert_input: 'convert_date',
          convert_output: 'convert_date',
          type: 'date'
        },
        {
          name: 'REVERSEDATE',
          label: 'Reverse date',
          hint: 'Reverse date must be greater than Batch date.',
          render_input: lambda do |field|
            field&.to_date&.strftime('%m/%d/%Y')
          end,
          parse_output: lambda do |field|
            field&.to_date(format: '%m/%d/%Y')
          end,
          type: 'date'
        },
        {
          name: 'BATCH_TITLE',
          label: 'Batch title',
          hint: 'Description of entry',
          sticky: true
        },
        {
          name: 'TAXIMPLICATIONS',
          label: 'Tax implications',
          hint: 'Tax implications. Use None, Inbound for purchase tax, ' \
          'or Outbound for sales tax.(AU, GB only)',
          control_type: 'select',
          pick_list: 'tax_implications',
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'TAXIMPLICATIONS',
            label: 'Tax implications',
            hint: 'Tax implications. Use None, Inbound for purchase tax, ' \
            'or Outbound for sales tax.(AU, GB only)',
            toggle_hint: 'Use custom value',
            optional: true,
            control_type: 'text',
            type: 'string'
          }
        },
        {
          name: 'VATVENDORID',
          label: 'VAT vendor ID',
          hint: 'Vendor ID when tax implications is set to Inbound for ' \
          'tax on purchases (AU, GB only)'
        },
        {
          name: 'VATCUSTOMERID',
          label: 'VAT customer ID',
          hint: 'Customer ID when tax implications is set to Outbound for ' \
          'tax on sales (AU, GB only)'
        },
        {
          name: 'VATCONTACTID',
          label: 'VAT contact ID',
          hint: 'Contact name for the customer SHIPTO contact for sales ' \
          'journals or the vendor ID for the vendor PAYTO contact for ' \
          'purchase journals (AU, GB only)'
        },
        {
          name: 'HISTORY_COMMENT',
          label: 'History comment',
          hint: 'Comment added to history for this transaction'
        },
        {
          name: 'REFERENCENO',
          label: 'Reference number of transaction',
          sticky: true
        },
        {
          name: 'BASELOCATION_NO',
          label: 'Baselocation number',
          hint: 'Source entity ID. Required if multi-entity enabled and ' \
            'entries do not balance by entity.',
          sticky: true
        },
        { name: 'SUPDOCID', label: 'Attachments ID' },
        {
          name: 'STATE',
          label: 'State',
          hint: 'State to update the entry to. Posted to post to the GL, ' \
            'otherwise Draft.',
          control_type: 'select',
          pick_list: 'update_gl_entry_states',
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'STATE',
            label: 'State',
            hint: 'Allowed values are: Draft, Posted',
            toggle_hint: 'Use custom value',
            optional: true,
            control_type: 'text',
            type: 'string'
          }
        },
        {
          name: 'ENTRIES',
          label: 'Entries',
          hint: 'Must have at least two lines (one debit, one credit).',
          type: 'object',
          properties: [{
            name: 'GLENTRY',
            label: 'GL Entry',
            hint: 'Must have at least two lines (one debit, one credit)',
            optional: false,
            type: 'array',
            of: 'object',
            properties: [
              { name: 'DOCUMENT', label: 'Document number' },
              { name: 'ACCOUNTNO', label: 'Account number', optional: false },
              {
                name: 'CURRENCY',
                label: 'Currency',
                hint: 'Transaction currency code. Required if ' \
                  'multi-currency enabled.'
              },
              {
                name: 'TRX_AMOUNT',
                label: 'Transaction amount',
                hint: 'Absolute value, relates to Transaction type.',
                optional: false,
                control_type: 'number',
                parse_output: 'float_conversion',
                type: 'number'
              },
              {
                name: 'TR_TYPE',
                label: 'Transaction type',
                optional: false,
                control_type: 'select',
                pick_list: 'tr_types',
                toggle_hint: 'Select from list',
                toggle_field: {
                  name: 'TR_TYPE',
                  label: 'Transaction type',
                  hint: 'Allowed values are: 1 (Debit), -1 (Credit).',
                  toggle_hint: 'Use custom value',
                  optional: false,
                  control_type: 'text',
                  type: 'string'
                }
              },
              {
                name: 'EXCH_RATE_DATE',
                label: 'Exchange rate date',
                hint: 'If null, defaults to Batch date',
                render_input: lambda do |field|
                  field&.to_date&.strftime('%m/%d/%Y')
                end,
                parse_output: lambda do |field|
                  field&.to_date(format: '%m/%d/%Y')
                end,
                type: 'date'
              },
              {
                name: 'EXCH_RATE_TYPE_ID',
                label: 'Exchange rate type ID',
                hint: 'Required if multi-currency ' \
                  'enabled and EXCHANGE_RATE left blank. ' \
                  '(Default Intacct Daily Rate)'
              },
              {
                name: 'EXCHANGE_RATE',
                label: 'Exchange rate',
                hint: 'Required if multi currency enabled ' \
                'and Exch rate type ID left blank. Exchange rate amount ' \
                'to 4 decimals.',
                control_type: 'number',
                parse_output: 'float_conversion',
                type: 'number'
              },
              {
                name: 'DESCRIPTION',
                label: 'Description',
                hint: 'Memo. If left blank, set this value to match Batch ' \
                'title.'
              },
              {
                name: 'ALLOCATION',
                label: 'Allocation ID',
                hint: 'All other dimension elements are ' \
                'ignored if allocation is set. Use `Custom` for ' \
                'custom splits and see `Split` element below.',
                sticky: true
              },
              {
                name: 'DEPARTMENT',
                label: 'Department',
                control_type: 'select',
                pick_list: 'departments',
                toggle_hint: 'Select from list',
                toggle_field: {
                  name: 'DEPARTMENT',
                  label: 'Department ID',
                  toggle_hint: 'Use custom value',
                  optional: true,
                  control_type: 'text',
                  type: 'string'
                }
              },
              {
                name: 'LOCATION',
                label: 'Location',
                hint: 'Required if multi-entity enabled',
                sticky: true,
                control_type: 'select',
                pick_list: 'locations',
                toggle_hint: 'Select from list',
                toggle_field: {
                  name: 'LOCATION',
                  label: 'Location ID',
                  toggle_hint: 'Use custom value',
                  optional: true,
                  control_type: 'text',
                  type: 'string'
                }
              },
              {
                name: 'PROJECTID',
                label: 'Project',
                control_type: 'select',
                pick_list: 'projects',
                toggle_hint: 'Select from list',
                toggle_field: {
                  name: 'PROJECTID',
                  label: 'Project ID',
                  toggle_hint: 'Use custom value',
                  optional: true,
                  control_type: 'text',
                  type: 'string'
                }
              },
              {
                name: 'TASKID',
                label: 'Task ID',
                hint: 'Task ID. Only available when the parent ' \
                'Project/Project ID is also specified.'
              },
              {
                name: 'CUSTOMERID',
                label: 'Customer',
                control_type: 'select',
                pick_list: 'customers',
                toggle_hint: 'Select from list',
                toggle_field: {
                  name: 'CUSTOMERID',
                  label: 'Customer ID',
                  toggle_hint: 'Use custom value',
                  optional: true,
                  control_type: 'text',
                  type: 'string'
                }
              },
              {
                name: 'VENDORID',
                label: 'Vendor',
                control_type: 'select',
                pick_list: 'vendors',
                toggle_hint: 'Select from list',
                toggle_field: {
                  name: 'VENDORID',
                  label: 'Vendor ID',
                  toggle_hint: 'Use custom value',
                  optional: true,
                  control_type: 'text',
                  type: 'string'
                }
              },
              {
                name: 'EMPLOYEEID',
                label: 'Employee',
                control_type: 'select',
                pick_list: 'employees',
                toggle_hint: 'Select from list',
                toggle_field: {
                  name: 'EMPLOYEEID',
                  label: 'Employee ID',
                  toggle_hint: 'Use custom value',
                  optional: true,
                  control_type: 'text',
                  type: 'string'
                }
              },
              {
                name: 'ITEMID',
                label: 'Item',
                control_type: 'select',
                pick_list: 'items',
                toggle_hint: 'Select from list',
                toggle_field: {
                  name: 'ITEMID',
                  label: 'Item ID',
                  toggle_hint: 'Use custom value',
                  optional: true,
                  control_type: 'text',
                  type: 'string'
                }
              },
              {
                name: 'CLASSID',
                label: 'Class',
                control_type: 'select',
                pick_list: 'classes',
                toggle_hint: 'Select from list',
                toggle_field: {
                  name: 'CLASSID',
                  label: 'Class ID',
                  toggle_hint: 'Use custom value',
                  optional: true,
                  control_type: 'text',
                  type: 'string'
                }
              },
              { name: 'CONTRACTID', label: 'Contract ID' },
              {
                name: 'WAREHOUSEID',
                label: 'Warehouse',
                control_type: 'select',
                pick_list: 'warehouses',
                toggle_hint: 'Select from list',
                toggle_field: {
                  name: 'WAREHOUSEID',
                  label: 'Warehouse ID',
                  toggle_hint: 'Use custom value',
                  optional: true,
                  control_type: 'text',
                  type: 'string'
                }
              },
              {
                name: 'BILLABLE',
                hint: 'Billable option for project-related transactions ' \
                'imported into the GL through external systems. Use Yes ' \
                'for billable transactions (Default: No)',
                control_type: 'checkbox',
                type: 'boolean',
                toggle_hint: 'Select from list',
                toggle_field: {
                  name: 'BILLABLE',
                  label: 'Billable',
                  hint: 'Billable option for project-related transactions ' \
                  'imported into the GL through external systems. Use true ' \
                  'for billable transactions (Default: false)',
                  toggle_hint: 'Use custom value',
                  optional: true,
                  control_type: 'text',
                  type: 'boolean'
                }
              },
              {
                name: 'SPLIT',
                label: 'Split',
                hint: 'Custom allocation split. Required if ALLOCATION ' \
                'equals Custom. Multiple SPLIT elements may then be passed.',
                sticky: true,
                type: 'array',
                of: 'object',
                properties: [
                  {
                    name: 'AMOUNT',
                    label: 'Amount',
                    hint: 'A required field. Split transaction amount. ' \
                    'Absolute value. All SPLIT element’s amount values ' \
                    'must sum up to equal GLENTRY element’s Transaction ' \
                    'amount',
                    sticky: true,
                    control_type: 'number',
                    parse_output: 'float_conversion',
                    type: 'number'
                  },
                  {
                    name: 'DEPARTMENT',
                    label: 'Department',
                    control_type: 'select',
                    pick_list: 'departments',
                    toggle_hint: 'Select from list',
                    toggle_field: {
                      name: 'DEPARTMENT',
                      label: 'Department ID',
                      toggle_hint: 'Use custom value',
                      optional: true,
                      control_type: 'text',
                      type: 'string'
                    }
                  },
                  {
                    name: 'LOCATION',
                    label: 'Location',
                    hint: 'Required if multi-entity enabled',
                    sticky: true,
                    control_type: 'select',
                    pick_list: 'locations',
                    toggle_hint: 'Select from list',
                    toggle_field: {
                      name: 'LOCATION',
                      label: 'Location ID',
                      toggle_hint: 'Use custom value',
                      optional: true,
                      control_type: 'text',
                      type: 'string'
                    }
                  },
                  {
                    name: 'PROJECTID',
                    label: 'Project',
                    control_type: 'select',
                    pick_list: 'projects',
                    toggle_hint: 'Select from list',
                    toggle_field: {
                      name: 'PROJECTID',
                      label: 'Project ID',
                      toggle_hint: 'Use custom value',
                      optional: true,
                      control_type: 'text',
                      type: 'string'
                    }
                  },
                  {
                    name: 'TASKID',
                    label: 'Task ID',
                    hint: 'Task ID. Only available when the parent ' \
                    'Project/Project ID is also specified.'
                  },
                  {
                    name: 'CUSTOMERID',
                    label: 'Customer',
                    control_type: 'select',
                    pick_list: 'customers',
                    toggle_hint: 'Select from list',
                    toggle_field: {
                      name: 'CUSTOMERID',
                      label: 'Customer ID',
                      toggle_hint: 'Use custom value',
                      optional: true,
                      control_type: 'text',
                      type: 'string'
                    }
                  },
                  {
                    name: 'VENDORID',
                    label: 'Vendor',
                    control_type: 'select',
                    pick_list: 'vendors',
                    toggle_hint: 'Select from list',
                    toggle_field: {
                      name: 'VENDORID',
                      label: 'Vendor ID',
                      toggle_hint: 'Use custom value',
                      optional: true,
                      control_type: 'text',
                      type: 'string'
                    }
                  },
                  {
                    name: 'EMPLOYEEID',
                    label: 'Employee',
                    control_type: 'select',
                    pick_list: 'employees',
                    toggle_hint: 'Select from list',
                    toggle_field: {
                      name: 'EMPLOYEEID',
                      label: 'Employee ID',
                      toggle_hint: 'Use custom value',
                      optional: true,
                      control_type: 'text',
                      type: 'string'
                    }
                  },
                  {
                    name: 'ITEMID',
                    label: 'Item',
                    control_type: 'select',
                    pick_list: 'items',
                    toggle_hint: 'Select from list',
                    toggle_field: {
                      name: 'ITEMID',
                      label: 'Item ID',
                      toggle_hint: 'Use custom value',
                      optional: true,
                      control_type: 'text',
                      type: 'string'
                    }
                  },
                  {
                    name: 'CLASSID',
                    label: 'Class',
                    control_type: 'select',
                    pick_list: 'classes',
                    toggle_hint: 'Select from list',
                    toggle_field: {
                      name: 'CLASSID',
                      label: 'Class ID',
                      toggle_hint: 'Use custom value',
                      optional: true,
                      control_type: 'text',
                      type: 'string'
                    }
                  },
                  { name: 'CONTRACTID', label: 'Contract ID' },
                  {
                    name: 'WAREHOUSEID',
                    label: 'Warehouse',
                    control_type: 'select',
                    pick_list: 'warehouses',
                    toggle_hint: 'Select from list',
                    toggle_field: {
                      name: 'WAREHOUSEID',
                      label: 'Warehouse ID',
                      toggle_hint: 'Use custom value',
                      optional: true,
                      control_type: 'text',
                      type: 'string'
                    }
                  }
                ]
              },
              {
                name: 'customfields',
                label: 'Custom fields/dimensions',
                sticky: true,
                type: 'array',
                of: 'object',
                properties: [{
                  name: 'customfield',
                  label: 'Custom field/dimension',
                  sticky: true,
                  type: 'array',
                  of: 'object',
                  properties: [
                    {
                      name: 'customfieldname',
                      label: 'Custom field/dimension name',
                      hint: 'Integration name of the custom field or ' \
                        'custom dimension. Find integration name in object ' \
                        'definition page of the respective object. Prepend ' \
                        "custom dimension with 'GLDIM'; e.g., if the " \
                        'custom dimension is Rating, use ' \
                        "'<b>GLDIM</b>Rating' as integration name here.",
                      sticky: true
                    },
                    {
                      name: 'customfieldvalue',
                      label: 'Custom field/dimension value',
                      hint: 'The value of custom field or custom dimension',
                      sticky: true
                    }
                  ]
                }]
              },
              {
                name: 'TAXENTRIES',
                label: 'Tax entries',
                hint: 'Tax entry for the line (AU, GB only).',
                sticky: true,
                type: 'array',
                of: 'object',
                properties: [
                  {
                    name: 'RECORDNO',
                    label: 'Record number',
                    hint: 'Record number of an existing tax entry ' \
                    '(associated with this line) that you want to modify. ' \
                    'You can omit this parameter to create a new tax entry.',
                    type: 'integer'
                  },
                  {
                    name: 'DETAILID',
                    label: 'Detail ID',
                    hint: 'Required field. Tax rate specified via the ' \
                    'unique ID of a tax detail.',
                    sticky: true
                  },
                  {
                    name: 'TRX_TAX',
                    label: 'Transaction tax',
                    hint: 'Transaction tax, which is your manually ' \
                    'calculated value for the tax.',
                    sticky: true,
                    control_type: 'number',
                    parse_output: 'float_conversion',
                    type: 'number'
                  }
                ]
              }
            ]
          }]
        },
        {
          name: 'customfields',
          label: 'Custom fields/dimensions',
          sticky: true,
          type: 'array',
          of: 'object',
          properties: [{
            name: 'customfield',
            label: 'Custom field/dimension',
            sticky: true,
            type: 'array',
            of: 'object',
            properties: [
              {
                name: 'customfieldname',
                label: 'Custom field/dimension name',
                hint: 'Integration name of the custom field or ' \
                  'custom dimension. Find integration name in object ' \
                  'definition page of the respective object. Prepend ' \
                  "custom dimension with 'GLDIM'; e.g., if the " \
                  'custom dimension is Rating, use ' \
                  "'<b>GLDIM</b>Rating' as integration name here.",
                sticky: true
              },
              {
                name: 'customfieldvalue',
                label: 'Custom field/dimension value',
                hint: 'The value of custom field or custom dimension',
                sticky: true
              }
            ]
          }]
        }
      ]
    end,

    invoice_create_schema: lambda do
      [
        {
          name: 'customerid',
          label: 'Customer',
          control_type: 'select',
          pick_list: 'customers',
          optional: false,
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'customerid',
            label: 'Customer ID',
            toggle_hint: 'Use custom value',
            control_type: 'text',
            optional: false,
            type: 'string'
          }
        },
        {
          name: 'datecreated',
          label: 'Date created',
          hint: 'Transaction date, a required field.',
          optional: false,
          type: 'object',
          properties: [
            {
              name: 'year',
              hint: 'Year in yyyy format',
              optional: false,
              control_type: 'integer',
              type: 'integer'
            },
            {
              name: 'month',
              hint: 'Month in mm format',
              optional: false,
              control_type: 'integer',
              type: 'integer'
            },
            {
              name: 'day',
              hint: 'Day in dd format',
              optional: false,
              control_type: 'integer',
              type: 'integer'
            }
          ]
        },
        {
          name: 'dateposted',
          label: 'Date posted',
          hint: 'GL posting date',
          type: 'object',
          properties: [
            {
              name: 'year',
              control_type: 'integer',
              type: 'integer',
              hint: 'Year in yyyy format'
            },
            {
              name: 'month',
              control_type: 'integer',
              type: 'integer',
              hint: 'Month in mm format'
            },
            {
              name: 'day',
              control_type: 'integer',
              type: 'integer',
              hint: 'Day in dd format'
            }
          ]
        },
        {
          name: 'datedue',
          label: 'Due date',
          sticky: true,
          type: 'object',
          hint: 'Required if not using <b>Payment term</b>',
          properties: [
            {
              name: 'year',
              control_type: 'integer',
              type: 'integer',
              hint: 'Year in yyyy format',
              sticky: true
            },
            {
              name: 'month',
              control_type: 'integer',
              type: 'integer',
              hint: 'Month in mm format',
              sticky: true
            },
            {
              name: 'day',
              control_type: 'integer',
              type: 'integer',
              hint: 'Day in dd format',
              sticky: true
            }
          ]
        },
        {
          name: 'termname',
          label: 'Payment term',
          hint: 'Required if not using <b>Due date</b>.',
          sticky: true
        },
        {
          name: 'batchkey',
          type: 'integer',
          label: 'Summary record number'
        },
        {
          name: 'action',
          hint: 'Default value is Submit',
          control_type: 'select',
          pick_list: 'invoice_actions',
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'action',
            label: 'Action',
            hint: 'Allowed values are: Draft, Submit. Default value is ' \
            'Submit.',
            toggle_hint: 'Use custom value',
            optional: true,
            control_type: 'text',
            type: 'string'
          }
        },
        { name: 'invoiceno', label: 'Invoice number' },
        { name: 'ponumber', label: 'Reference number' },
        { name: 'description' },
        { name: 'externalid', label: 'External ID' },
        {
          name: 'billto',
          label: 'Bill to contact',
          type: 'object',
          properties: [{ name: 'contactname', label: 'Contact number' }]
        },
        {
          name: 'shipto',
          label: 'Ship to contact',
          type: 'object',
          properties: [{ name: 'contactname', label: 'Contact number' }]
        },
        {
          name: 'basecurr',
          label: 'Base currency code',
          hint: 'e.g. USD for US Dollars',
          sticky: true
        },
        {
          name: 'currency',
          label: 'Transaction currency code',
          hint: 'e.g. USD for US Dollars',
          sticky: true
        },
        {
          name: 'exchratedate',
          label: 'Exchange rate date',
          type: 'object',
          sticky: true,
          properties: [
            {
              name: 'year',
              control_type: 'integer',
              type: 'integer',
              hint: 'Year in yyyy format',
              sticky: true
            },
            {
              name: 'month',
              control_type: 'integer',
              type: 'integer',
              hint: 'Month in mm format',
              sticky: true
            },
            {
              name: 'day',
              control_type: 'integer',
              type: 'integer',
              hint: 'Day in dd format',
              sticky: true
            }
          ]
        },
        {
          name: 'exchratetype',
          label: 'Exchange rate type',
          hint: 'Do not use if exchange rate is set.',
          sticky: true
        },
        {
          name: 'exchrate',
          label: 'Exchange rate',
          hint: 'Do not use if exchange rate type is set.',
          sticky: true
        },
        {
          name: 'nogl',
          label: 'Do not post to GL',
          hint: 'Default: No',
          control_type: 'checkbox',
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'nogl',
            label: 'Do not post to GL',
            hint: 'Use false for No, true for Yes. (Default: false)',
            toggle_hint: 'Use custom value',
            optional: true,
            control_type: 'text',
            type: 'string'
          }
        },
        { name: 'supdocid', label: 'Attachments ID' },
        {
          name: 'customfields',
          label: 'Custom fields/dimensions',
          type: 'array',
          of: 'object',
          properties: [{
            name: 'customfield',
            label: 'Custom field/dimension',
            type: 'array',
            of: 'object',
            properties: [
              {
                name: 'customfieldname',
                label: 'Custom field/dimension name',
                hint: 'Integration name of the custom field or ' \
                  'custom dimension. Find integration name in object ' \
                  'definition page of the respective object. Prepend ' \
                  "custom dimension with 'GLDIM'; e.g., if the " \
                  'custom dimension is Rating, use ' \
                  "'<b>GLDIM</b>Rating' as integration name here."
              },
              {
                name: 'customfieldvalue',
                label: 'Custom field/dimension value',
                hint: 'The value of custom field or custom dimension'
              }
            ]
          }]
        },
        {
          name: 'taxsolutionid',
          label: 'Tax solution ID',
          hint: 'Tax solution name, such as <b>United Kingdom - VAT or ' \
          'Australia - GST</b>. Required only if the company is configured ' \
          'for multiple tax jurisdictions and the transaction is occurring ' \
          'at the top level of the company. The available tax solution names ' \
          'can be found in the Sage Intacct UI in the Taxes application ' \
          'from the top level of a multi-entity company. (GB, AU, and ZA only)'
        },
        {
          name: 'invoiceitems',
          label: 'Invoice lines',
          hint: 'Invoice lines, must have at least 1.',
          optional: false,
          type: 'array',
          of: 'object',
          properties: [
            {
              name: 'lineitem',
              label: 'Line item',
              optional: false,
              type: 'array',
              of: 'object',
              properties: [
                {
                  name: 'glaccountno',
                  label: 'GL account number',
                  hint: 'Required if not using AR account label.',
                  sticky: true
                },
                {
                  name: 'accountlabel',
                  label: 'AR account label',
                  hint: 'Required if not using GL account number',
                  sticky: true
                },
                {
                  name: 'offsetglaccountno',
                  label: 'Offset GL account number'
                },
                {
                  name: 'amount',
                  label: 'Transaction amount',
                  optional: false,
                  type: 'number'
                },
                { name: 'allocationid', label: 'Allocation ID' },
                { name: 'memo' },
                {
                  name: 'locationid',
                  label: 'Location',
                  sticky: true,
                  control_type: 'select',
                  pick_list: 'locations',
                  toggle_hint: 'Select from list',
                  toggle_field: {
                    name: 'locationid',
                    label: 'Location ID',
                    toggle_hint: 'Use custom value',
                    optional: true,
                    control_type: 'text',
                    type: 'string'
                  }
                },
                {
                  name: 'departmentid',
                  label: 'Department',
                  sticky: true,
                  control_type: 'select',
                  pick_list: 'departments',
                  toggle_hint: 'Select from list',
                  toggle_field: {
                    name: 'departmentid',
                    label: 'Department ID',
                    toggle_hint: 'Use custom value',
                    optional: true,
                    control_type: 'text',
                    type: 'string'
                  }
                },
                { name: 'key' },
                {
                  name: 'totalpaid',
                  label: 'Total paid',
                  hint: 'Used when </b>Do not post to GL</b> on bill is true'
                },
                {
                  name: 'totaldue',
                  label: 'Total due',
                  hint: 'Used when </b>Do not post to GL</b> on bill is true'
                },
                {
                  name: 'customfields',
                  label: 'Custom fields/dimensions',
                  sticky: true,
                  type: 'array',
                  of: 'object',
                  properties: [{
                    name: 'customfield',
                    label: 'Custom field/dimension',
                    sticky: true,
                    type: 'array',
                    of: 'object',
                    properties: [
                      {
                        name: 'customfieldname',
                        label: 'Custom field/dimension name',
                        hint: 'Integration name of the custom field or ' \
                          'custom dimension. Find integration name in object ' \
                          'definition page of the respective object. Prepend ' \
                          "custom dimension with 'GLDIM'; e.g., if the " \
                          'custom dimension is Rating, use ' \
                          "'<b>GLDIM</b>Rating' as integration name here.",
                        sticky: true
                      },
                      {
                        name: 'customfieldvalue',
                        label: 'Custom field/dimension value',
                        hint: 'The value of custom field or custom dimension',
                        sticky: true
                      }
                    ]
                  }]
                },
                { name: 'revrectemplate', label: 'Rev rec template ID' },
                {
                  name: 'defrevaccount',
                  label: 'Deferred revenue GL account number'
                },
                {
                  name: 'revrecstartdate',
                  label: 'Rev-rec start date',
                  type: 'object',
                  properties: [
                    {
                      name: 'year',
                      control_type: 'integer',
                      type: 'integer',
                      hint: 'Year in yyyy format'
                    },
                    {
                      name: 'month',
                      control_type: 'integer',
                      type: 'integer',
                      hint: 'Month in mm format'
                    },
                    {
                      name: 'day',
                      control_type: 'integer',
                      type: 'integer',
                      hint: 'Day in dd format'
                    }
                  ]
                },
                {
                  name: 'revrecenddate',
                  label: 'Rev-rec end date',
                  type: 'object',
                  properties: [
                    {
                      name: 'year',
                      control_type: 'integer',
                      type: 'integer',
                      hint: 'Year in yyyy format'
                    },
                    {
                      name: 'month',
                      control_type: 'integer',
                      type: 'integer',
                      hint: 'Month in mm format'
                    },
                    {
                      name: 'day',
                      control_type: 'integer',
                      type: 'integer',
                      hint: 'Day in dd format'
                    }
                  ]
                },
                {
                  name: 'projectid',
                  label: 'Project',
                  control_type: 'select',
                  pick_list: 'projects',
                  toggle_hint: 'Select from list',
                  toggle_field: {
                    name: 'projectid',
                    label: 'Project ID',
                    toggle_hint: 'Use custom value',
                    control_type: 'text',
                    optional: true,
                    type: 'string'
                  }
                },
                {
                  name: 'taskid',
                  label: 'Task ID',
                  hint: 'Only available when the parent <b>Project ID</b> ' \
                  'is also specified.'
                },
                {
                  name: 'costtypeid',
                  label: 'Cost type ID',
                  hint: 'Only available when the parent <b>Project ID and ' \
                  'Task ID </b> are specified.'
                },
                {
                  name: 'customerid',
                  label: 'Customer',
                  control_type: 'select',
                  pick_list: 'customers',
                  toggle_hint: 'Select from list',
                  toggle_field: {
                    name: 'customerid',
                    label: 'Customer ID',
                    toggle_hint: 'Use custom value',
                    control_type: 'text',
                    optional: true,
                    type: 'string'
                  }
                },
                {
                  name: 'vendorid',
                  label: 'Vendor',
                  control_type: 'select',
                  pick_list: 'vendors',
                  toggle_hint: 'Select from list',
                  toggle_field: {
                    name: 'vendorid',
                    label: 'Vendor ID',
                    toggle_hint: 'Use custom value',
                    control_type: 'text',
                    optional: true,
                    type: 'string'
                  }
                },
                {
                  name: 'employeeid',
                  label: 'Employee',
                  control_type: 'select',
                  pick_list: 'employees',
                  toggle_hint: 'Select from list',
                  toggle_field: {
                    name: 'employeeid',
                    label: 'Employee ID',
                    toggle_hint: 'Use custom value',
                    optional: true,
                    control_type: 'text',
                    type: 'string'
                  }
                },
                {
                  name: 'itemid',
                  label: 'Item',
                  control_type: 'select',
                  pick_list: 'items',
                  toggle_hint: 'Select from list',
                  toggle_field: {
                    name: 'itemid',
                    label: 'Item ID',
                    toggle_hint: 'Use custom value',
                    optional: true,
                    control_type: 'text',
                    type: 'string'
                  }
                },
                {
                  name: 'classid',
                  label: 'Class',
                  control_type: 'select',
                  pick_list: 'classes',
                  toggle_hint: 'Select from list',
                  toggle_field: {
                    name: 'classid',
                    label: 'Class ID',
                    toggle_hint: 'Use custom value',
                    optional: true,
                    control_type: 'text',
                    type: 'string'
                  }
                },
                {
                  name: 'warehouseid',
                  label: 'Warehouse',
                  control_type: 'select',
                  pick_list: 'warehouses',
                  toggle_hint: 'Select from list',
                  toggle_field: {
                    name: 'warehouseid',
                    label: 'Warehouse ID',
                    toggle_hint: 'Use custom value',
                    optional: true,
                    control_type: 'text',
                    type: 'string'
                  }
                },
                {
                  name: 'taxentries',
                  label: 'Tax entries',
                  type: 'array',
                  of: 'object',
                  properties: [{
                    name: 'taxentry',
                    label: 'Tax entry',
                    type: 'array',
                    of: 'object',
                    properties: [
                      {
                        name: 'detailid',
                        label: 'Detail ID',
                        hint: "Unique ID of a <a href='https://developer" \
                        ".intacct.com/api/general-ledger/tax-details/' target" \
                        "='_blank'>tax detail</a> with the tax rate to use"
                      },
                      {
                        name: 'trx_tax',
                        label: 'Transaction tax',
                        hint: 'Transaction tax, which is a manually ' \
                        'calculated value to override the calculated value ' \
                        'for the tax. The amount of the tax line is ' \
                        'automatically included in the amount due ' \
                        '(TOTAL_DUE) for the invoice',
                        type: 'number'
                      }
                    ]
                  }]
                }
              ]
            }
          ]
        }
      ]
    end,

    timesheet_entry_schema: lambda do
      [
        {
          name: 'LINENO',
          label: 'Line number',
          hint: 'Line number to add entry to',
          sticky: true,
          control_type: 'integer',
          type: 'integer'
        },
        { name: 'CUSTOMERID', label: 'Customer ID' },
        { name: 'ITEMID', label: 'Item ID' },
        { name: 'PROJECTID', label: 'Project ID', sticky: true },
        { name: 'TASKID', label: 'Task ID', sticky: true,
          hint: 'Do not use if <b>Task key</b> is set' },
        { name: 'TASKKEY', type: 'integer', label: 'Task key',
          hint: 'Do not use if <b>Task ID</b> is set.' },
        { name: 'COSTTYPEID', label: 'Cost type ID',
          hint: 'Only available when Project ID and task are specified.' },
        { name: 'TIMETYPE', label: 'Time type' },
        { name: 'BILLABLE', label: 'Billable', control_type: 'checkbox',
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'BILLABLE',
            type: 'string',
            control_type: 'text',
            optional: true,
            label: 'Billable',
            toggle_hint: 'Use custom value',
            hint: 'Allowed values are: true, false'
          } },
        { name: 'LOCATIONID', label: 'Location', sticky: true,
          control_type: 'select', pick_list: 'locations',
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'LOCATIONID',
            label: 'Location ID',
            toggle_hint: 'Use custom value',
            control_type: 'text',
            optional: true,
            type: 'string'
          } },
        { name: 'DEPARTMENTID', label: 'Department',
          control_type: 'select', pick_list: 'departments',
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'DEPARTMENTID',
            label: 'Department ID',
            toggle_hint: 'Use custom value',
            control_type: 'text',
            optional: true,
            type: 'string'
          } },
        { name: 'ENTRYDATE', type: 'date', label: 'Entry date',
          control_type: 'date', sticky: true,
          convert_input: 'convert_date',
          convert_output: 'convert_date',
          hint: 'Entry date in format mm/dd/yyyy. This field is ' \
          '<b>required</b> to create/update <b>timesheet entries</b>.' },
        { name: 'QTY', type: 'number', label: 'Hours/Quantity', sticky: true,
          hint: 'This field is <b>required</b> to create/update <b>timesheet entries</b>.' },
        { name: 'DESCRIPTION', label: 'Description' },
        { name: 'NOTES', label: 'Notes' },
        { name: 'VENDORID', label: 'Vendor',
          control_type: 'select', pick_list: 'vendors',
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'VENDORID',
            label: 'Vendor ID',
            toggle_hint: 'Use custom value',
            control_type: 'text',
            optional: true,
            type: 'string'
          } },
        { name: 'CLASSID', label: 'Class',
          control_type: 'select', pick_list: 'classes',
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'CLASSID',
            label: 'Class ID',
            toggle_hint: 'Use custom value',
            control_type: 'text',
            optional: true,
            type: 'string'
          } },
        { name: 'CONTRACTID', label: 'Contract ID' },
        { name: 'WAREHOUSEID', label: 'Warehouse',
          control_type: 'select', pick_list: 'warehouses',
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'WAREHOUSEID',
            label: 'Warehouse ID',
            toggle_hint: 'Use custom value',
            control_type: 'text',
            optional: true,
            type: 'string'
          } },
        { name: 'EXTBILLRATE', type: 'number', label: 'External bill rate' },
        { name: 'EXTCOSTRATE', type: 'number', label: 'External cost rate' }
      ].concat(call('get_custom_fields', 'TIMESHEETENTRY')).compact
    end,

    query_schema: lambda do |fields|
      [
        {
          name: 'fields',
          control_type: 'multiselect',
          delimiter: ',',
          sticky: true,
          pick_list: fields,
          toggle_hint: 'Select from options',
          hint: 'The list of fields to include in the result. ' \
          'All fields will be returned by default.',
          toggle_field: {
            name: 'fields',
            label: 'Field names',
            type: 'string',
            control_type: 'text',
            optional: false,
            toggle_hint: 'Use custom value',
            hint: 'Enter field names separated by comma.'
          }
        },
        {
          name: 'filters', list_mode: 'static', sticky: true,
          type: :array, optional: true,
          properties: [
            {
              name: 'field', optional: false, control_type: 'select',
              pick_list: fields,
              toggle_hint: 'Select from options',
              hint: 'The field to filter on.',
              toggle_field: {
                name: 'field', label: 'Field name', type: 'string',
                control_type: 'text',
                toggle_hint: 'Use custom value',
                hint: "Enter field name. Click <a href='https://developers" \
                  '.google.com/adwords/api/docs/appendix/reports#available' \
                  "-reports' target='_blank'>here</a> for more details."
              }
            },
            {
              name: 'operator', optional: false, control_type: 'select',
              pick_list: 'filter_operators',
              toggle_hint: 'Select from options',
              hint: 'The operator used to filter on. ' \
              "<a href='https://developer.intacct.com/web-services/queries/#filter' " \
              "target='_blank'>Learn more</a>",
              toggle_field: {
                name: 'operator', label: 'Operator', type: 'string',
                control_type: 'text', toggle_hint: 'Use custom value',
                hint: 'Enter operator to be used. ' \
                "<a href='https://developer.intacct.com/web-services/queries/#filter' " \
                "target='_blank'>Learn more</a>"
              }
            },
            {
              name: 'value', optional: false,
              hint: 'The value(s) used to filter on.<br>Operators <b>between</b>, ' \
                '<b>in</b>, and <b>not in</b> take multiple ' \
                'values. All others take a single value. Specify ' \
                'them separated by commas, without any spaces. ' \
                "<a href='https://developer.intacct.com/web-services/queries/#examples' " \
                "target='_blank'>Learn more</a>"
            }
          ],
          item_label: 'Filter', add_item_label: 'Add another filter',
          empty_list_title: 'Specify filters',
          empty_list_text: 'Click the button below to add filters.',
          hint: 'Limit the response to only objects that match the expression.'
        },
        {
          name: 'filter_condition', sticky: true, control_type: 'select',
          pick_list: 'filter_conditions',
          toggle_hint: 'Select from options',
          hint: 'The operator to be used for combining statements for complex queries. ' \
          'Default value is <b>and</b>.',
          toggle_field: {
            name: 'filter_condition', label: 'Filter condition', type: 'string',
            control_type: 'text',
            toggle_hint: 'Use custom value',
            optional: true,
            hint: 'Allowed values are: and, or.'
          }
        },
        {
          name: 'ordering', sticky: true, type: 'object', properties: [
            {
              name: 'sort_field',
              sticky: true,
              control_type: 'select',
              pick_list: fields,
              toggle_hint: 'Select from options',
              hint: 'The field to sort on.',
              toggle_field: {
                name: 'sort_field', label: 'Sort field name', type: 'string',
                control_type: 'text',
                optional: true,
                toggle_hint: 'Use custom value',
                hint: 'Enter field name.'
              }
            },
            {
              name: 'sort_order',
              sticky: true,
              control_type: 'select',
              hint: 'The order to sort the results on.',
              pick_list: 'sort_orders',
              toggle_hint: 'Select from options',
              toggle_field: {
                name: 'sort_order',
                label: 'Sort order',
                type: 'string',
                optional: true,
                control_type: 'text',
                toggle_hint: 'Use custom value',
                hint: 'Allowed values are: descending, ascending'
              }
            }
          ]
        },
        {
          name: 'options', sticky: true, type: 'object',
          hint: 'Please select one option at a time.',
          properties: [
            {
              name: 'caseinsensitive',
              label: 'Case insensitive',
              type: 'boolean',
              control_type: 'checkbox',
              sticky: true,
              toggle_hint: 'Select from options',
              hint: 'Select <b>Yes</b> for a case-insensitive query.',
              toggle_field: {
                name: 'caseinsensitive',
                label: 'Case insensitive',
                type: 'string',
                control_type: 'text',
                optional: true,
                toggle_hint: 'Use custom value',
                hint: 'Allowed values are: true and false.'
              }
            },
            {
              name: 'showprivate',
              label: 'Show private',
              type: 'boolean',
              control_type: 'checkbox',
              sticky: true,
              toggle_hint: 'Select from options',
              hint: 'Select <b>Yes</b> to query data in private entities.',
              toggle_field: {
                name: 'showprivate',
                label: 'Show private',
                type: 'string',
                control_type: 'text',
                optional: true,
                toggle_hint: 'Use custom value',
                hint: 'Allowed values are: true and false.'
              }
            }
          ]
        },
        {
          name: 'offset',
          label: 'Offset',
          sticky: true,
          type: 'integer',
          control_type: 'integer',
          hint: 'Point at which to start indexing into records. The default value is 0.'
        },
        {
          name: 'pagesize',
          label: 'Page size',
          sticky: true,
          type: 'integer',
          control_type: 'integer',
          hint: 'Maximum number of results to return in this page. ' \
          'Set this to a reasonable value to limit the number of results returned per page.<br>' \
          'The default value is 100. Max value is 2000.'
        }
      ]
    end
  },

  connection: {
    fields: [
      { name: 'company_id', optional: false },
      { name: 'login_username', optional: false },
      {
        name: 'login_password',
        hint: 'Make sure the password does not contain special characters ' \
        "such as - \" , ', &, <, and >.",
        optional: false,
        control_type: 'password'
      },
      { name: 'sender_id', optional: false },
      {
        name: 'sender_password',
        hint: 'Make sure the password does not contain special characters ' \
        "such as - \" , ', &, <, and >.",
        optional: false,
        control_type: 'password'
      },
      {
        name: 'location_id',
        hint: 'If not specified, it takes the top-level (all entities). ' \
        'Only applicable to Multi-entity companies.',
        sticky: true
      }
    ],

    authorization: {
      type: 'custom_auth',

      acquire: lambda do |connection|
        payload = {
          'control' => {
            'senderid' => connection['sender_id'],
            'password' => connection['sender_password'],
            'controlid' => 'testControlId',
            'uniqueid' => false,
            'dtdversion' => 3.0
          },
          'operation' => {
            'authentication' => {
              'login' => {
                'userid' => connection['login_username'],
                'companyid' => connection['company_id'],
                'password' => connection['login_password'],
                'locationid' => connection['location_id']
              }.compact
            },
            'content' => {
              'function' => {
                '@controlid' => 'testControlId',
                'getAPISession' => ''
              }
            }
          }
        }.compact
        response_data = post('https://api.intacct.com/ia/xml/xmlgw.phtml',
                             payload).
                        headers('Content-Type' => 'x-intacct-xml-request').
                        format_xml('request').
                        dig('response', 0,
                            'operation', 0,
                            'result', 0,
                            'data', 0)
        api_data = call('parse_xml_to_hash',
                        'xml' => response_data,
                        'array_fields' => ['api'])&.
                        dig('api', 0)

        {
          session_id: api_data&.[]('sessionid'),
          endpoint: api_data&.[]('endpoint')
        }
      end,

      refresh_on: [400, 401, /Invalid session/, /XL03000006/],

      detect_on: [/Invalid session/, /XL03000006/],

      apply: lambda do |connection|
        headers('Content-Type' => 'x-intacct-xml-request')
        payload do |current_payload|
          current_payload&.[]=(
            'control',
            {
              'senderid' => connection['sender_id'],
              'password' => connection['sender_password'],
              'controlid' =>
              current_payload&.dig('control', 'controlid') || 'testControlId',
              'uniqueid' =>
              current_payload&.dig('control', 'uniqueid') || false,
              'dtdversion' =>
              current_payload&.dig('control', 'dtdversion') || '3.0'
            }
          )
          current_payload&.[]('operation')&.[]=(
            'authentication', {
              'sessionid' => connection['session_id']
            }
          )
        end
      end
    },

    base_uri: lambda do |_connection|
      'https://api.intacct.com/'
    end
  },

  test: lambda do |connection|
    payload = { 'control' => {}, 'operation' => { 'authentication' => {} } }
    response = post(call('get_endpoint_url', connection), payload).
               format_xml('request').
               after_error_response(/.*/) do |_code, body, _headers, message|
      error("{ \"error\": \"#{message}\", \"details\": \"#{body}\" }")
    end

    call('validate_intacct_response_auth_error', response)
  end,

  object_definitions: {
    # AR Adjustment
    ar_adjustment_create: {
      fields: lambda do |_connection, _config_fields|
        {
          name: 'create_aradjustment',
          label: 'Create AR adjustment',
          optional: false,
          type: 'object',
          properties: call('ar_adjustment_create_schema')
        }
      end
    },

    ar_adjustments_batch_create_input: {
      fields: lambda do |_connection, _config_fields|
        function_data = {
          name: 'create_aradjustment',
          label: 'Create AR adjustment',
          optional: false,
          type: 'object',
          properties: call('ar_adjustment_create_schema')
        }

        call('batch_input_schema',
             'function_name' => 'AR adjustments batch',
             'function_data' => function_data)
      end
    },

    # AR Payment
    ar_payment: {
      fields: lambda do |_connection, _config_fields|
        function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'ARPYMT' }
        }
        response_data = call('get_api_response_data_element', function)
        call('format_schema',
             call('get_object_definition',
                  call('parse_xml_to_hash',
                       'xml' => response_data,
                       'array_fields' => ['Field'])&.
                    dig('Type', 'Fields', 'Field')))
      end
    },

    ar_payment_search: {
      fields: lambda do |_connection, _config_fields|
        function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'ARPYMT' }
        }
        response_data = call('get_api_response_data_element', function)

        fields =
          call('parse_xml_to_hash',
               'xml' => response_data,
               'array_fields' => ['Field'])&.
          dig('Type', 'Fields', 'Field')&.
          reject { |item| %w[CUSTENTITY].include?(item['Name']) }&.
            map do |field|
              [field['DisplayLabel'], field['Name']]
            end
        call('query_schema', fields)
      end
    },

    ar_payment_create: {
      fields: lambda do |_connection, _config_fields|
        call('ar_payment_create_schema')
      end
    },

    ar_payments_batch_create_input: {
      fields: lambda do |_connection, _config_fields|
        function_data = {
          name: 'create_arpayment',
          label: 'Create AR payment',
          optional: false,
          type: 'object',
          properties: call('ar_payment_create_schema')
        }

        call('batch_input_schema',
             'function_name' => 'AR payments batch',
             'function_data' => function_data)
      end
    },

    # Bank Feed
    bank_feed: {
      fields: lambda do |_connection, _config_fields|
        [
          { name: 'RECORDNO', label: 'Record number', sticky: true },
          { name: 'FINANCIALENTITY', label: 'Bank account ID', sticky: true },
          {
            name: 'FINANCIALENTITYNAME',
            label: 'Bank account name',
            sticky: true
          },
          { name: 'FINACCTTXNFEEDKEY', label: 'Account transaction feed key' },
          { name: 'TRANSACTIONID', label: 'Transaction ID' },
          {
            name: 'BANKACCTRECONKEY',
            label: 'Bank account reconciliation key'
          },
          {
            name: 'POSTINGDATE',
            label: 'Posting date',
            convert_input: 'convert_date',
            parse_output: lambda do |field|
              field&.to_date(format: '%m/%d/%Y %H:%M:%S')
            end,
            type: 'date'
          },
          {
            name: 'TRANSACTIONTYPE',
            label: 'Transaction type',
            control_type: 'select',
            pick_list: 'transaction_types',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'TRANSACTIONTYPE',
              label: 'Transaction type',
              hint: 'Allowed values are: deposit, withdrawal.',
              toggle_hint: 'Use custom value',
              control_type: 'text',
              optional: true,
              type: 'string'
            }
          },
          { name: 'DOCTYPE', label: 'Document type' },
          { name: 'DOCNO', label: 'Document number' },
          { name: 'PAYEE', label: 'Payee' },
          {
            name: 'AMOUNT',
            label: 'Transaction amount',
            hint: 'For a withdrawal, use a negative number.',
            control_type: 'number',
            type: 'number'
          },
          { name: 'DESCRIPTION', label: 'Description', sticky: true },
          { name: 'CLEARED', label: 'Cleared' },
          { name: 'AMOUNTTOMATCH', label: 'Amount to match' },
          { name: 'RECORDDATA', label: 'Record data' },
          {
            name: 'WHENCREATED',
            label: 'When created',
            convert_input: 'convert_date',
            convert_output: 'convert_date',
            type: 'date'
          },
          {
            name: 'WHENMODIFIED',
            label: 'When modified',
            convert_input: 'convert_date',
            convert_output: 'convert_date',
            type: 'date'
          },
          { name: 'CREATEDBY', label: 'Created by' },
          { name: 'MODIFIEDBY', label: 'Modified by' },
          {
            name: 'FEEDTYPE',
            label: 'Feed type',
            control_type: 'select',
            default: 'xml',
            pick_list: 'feed_types',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'FEEDTYPE',
              label: 'Feed type',
              hint: 'Allowed values are: onl, xml.',
              toggle_hint: 'Use custom value',
              control_type: 'text',
              optional: true,
              type: 'string'
            }
          },
          { name: 'CURRENCY', label: 'Currency' }
        ]
      end
    },

    bank_feed_create: {
      fields: lambda do |_connection, _config_fields|
        [
          {
            name: 'FINANCIALENTITY',
            label: 'Bank account ID',
            optional: false
          },
          {
            name: 'FEEDDATE',
            label: 'Feed date',
            convert_input: 'convert_date',
            convert_output: 'convert_date',
            optional: false,
            type: 'date'
          },
          {
            name: 'FEEDTYPE',
            label: 'Feed type',
            control_type: 'select',
            default: 'xml',
            optional: false,
            pick_list: 'feed_types',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'FEEDTYPE',
              label: 'Feed type',
              hint: 'Allowed values are: onl, xml.',
              toggle_hint: 'Use custom value',
              control_type: 'text',
              optional: false,
              type: 'string'
            }
          },
          {
            name: 'FILENAME',
            label: 'File name',
            hint: 'File name that displays in the UI when using automatch ' \
            'with review (AutomatchReview) as the reconciliation mode.'
          },
          {
            name: 'BANKACCTTXNRECORDS',
            label: 'Bank account transaction records',
            hint: 'Required only if the feed type is xml.',
            sticky: true,
            type: 'array',
            of: 'object',
            properties: [
              {
                name: 'BANKACCTTXNRECORD',
                label: 'Bank account transaction record',
                sticky: true,
                type: 'array',
                of: 'object',
                properties: [
                  { name: 'TRANSACTIONID', label: 'Transaction ID' },
                  {
                    name: 'POSTINGDATE',
                    label: 'Posting date',
                    render_input: lambda do |field|
                      field&.to_date&.strftime('%m/%d/%Y')
                    end,
                    parse_output: lambda do |field|
                      field&.to_date(format: '%m/%d/%Y %H:%M:%S')
                    end,
                    sticky: true,
                    type: 'date'
                  },
                  {
                    name: 'TRANSACTIONTYPE',
                    label: 'Transaction type',
                    hint: 'Required only if the feed type is xml',
                    control_type: 'select',
                    sticky: true,
                    pick_list: 'transaction_types',
                    toggle_hint: 'Select from list',
                    toggle_field: {
                      name: 'TRANSACTIONTYPE',
                      label: 'Transaction type',
                      hint: 'Allowed values are: deposit, withdrawal.',
                      toggle_hint: 'Use custom value',
                      control_type: 'text',
                      sticky: true,
                      optional: true,
                      type: 'string'
                    }
                  },
                  { name: 'DOCTYPE', label: 'Document type', sticky: true },
                  { name: 'DOCNO', label: 'Document number' },
                  { name: 'PAYEE', label: 'Payee' },
                  {
                    name: 'AMOUNT',
                    label: 'Transaction amount',
                    hint: 'For a withdrawal, use a negative number.',
                    control_type: 'number',
                    sticky: true,
                    type: 'number'
                  },
                  { name: 'DESCRIPTION', label: 'Description', sticky: true },
                  { name: 'CURRENCY', label: 'Currency' }
                ]
              }
            ]
          }
        ]
      end
    },

    # Custom action
    custom_action_input: {
      fields: lambda do |_connection, config_fields|
        [
          {
            name: 'action_name',
            hint: "Give this action you're building a descriptive name, e.g. " \
            'Create customer, Get customer',
            default: 'Custom action',
            optional: false,
            extends_schema: true,
            schema_neutral: true
          },
          {
            name: 'control_element',
            label: 'Control element of XML request',
            hint: 'Control element includes your Web Services credentials ' \
            'and applies to the entire request. ' \
            "<a href='https://developer." \
            "intacct.com/web-services/requests/#control-element' " \
            "target='_blank'>Learn more</a>",
            type: 'object',
            properties: [
              {
                name: 'controlid',
                label: 'Control ID',
                hint: 'Control ID for request as a whole.'
              },
              {
                name: 'uniqueid',
                label: 'Unique ID',
                hint: 'Used in conjuction with "Control ID". Specifies ' \
                'whether a request can be submitted more than once without ' \
                'an error.When set to Yes, which is the default, a ' \
                'request cannot be repeated. The "Control ID" attribute of ' \
                'the <function> element will be checked to determine if ' \
                'the operation was previously executed and completed. When ' \
                'set to No, the system allows the operation to execute ' \
                'any number of times.',
                control_type: 'checkbox',
                type: 'boolean',
                toggle_hint: 'Select from list',
                toggle_field: {
                  name: 'uniqueid',
                  label: 'Unique ID',
                  hint: 'Used in conjuction with "Control ID". Specifies ' \
                  'whether a request can be submitted more than once without ' \
                  'an error.When set to true, which is the default, a ' \
                  'request cannot be repeated. The "Control ID" attribute of ' \
                  'the <function> element will be checked to determine if ' \
                  'the operation was previously executed and completed. When ' \
                  'set to false, the system allows the operation to execute ' \
                  'any number of times.',
                  toggle_hint: 'Use custom value',
                  optional: true,
                  control_type: 'text',
                  type: 'string'
                }
              },
              {
                name: 'dtdversion',
                label: 'DTD version',
                hint: 'Identifies the version of the API in use. The value ' \
                'of 3.0 (default) is strongly recommended as it ' \
                'provides access to both the generic functions and the ' \
                'object-specific functions.',
                control_type: 'select',
                pick_list: [%w[3.0 3.0], %w[2.1 2.1]]
              }
            ]
          },
          {
            name: 'operation_element',
            label: 'Operation element of XML request',
            hint: 'Provides the content for the request. ' \
            "<a href='https://developer." \
            "intacct.com/web-services/requests/#operation-element' " \
            "target='_blank'>Learn more</a>",
            optional: false,
            type: 'object',
            properties: [
              {
                name: 'transaction',
                label: 'Transaction',
                hint: 'Specifies whether all the functions in the ' \
                'operation block represent a single transaction. When set ' \
                'to Yes, all of the functions are treated as a single ' \
                'transaction. If one function fails, all previously ' \
                'executed functions within the operation are rolled back. ' \
                'This is useful for groups of functions that rely on each ' \
                'other to change information in the database. When set to ' \
                'No, which is the default, functions execute ' \
                'independently. If one function fails, others still proceed.',
                control_type: 'checkbox',
                type: 'boolean',
                toggle_hint: 'Select from list',
                toggle_field: {
                  name: 'transaction',
                  label: 'Transaction',
                  hint: 'Specifies whether all the functions in the ' \
                  'operation block represent a single transaction. When set ' \
                  'to true, all of the functions are treated as a single ' \
                  'transaction. If one function fails, all previously ' \
                  'executed functions within the operation are rolled back. ' \
                  'This is useful for groups of functions that rely on each ' \
                  'other to change information in the database. When set to ' \
                  'false, which is the default, functions execute ' \
                  'independently. If one function fails, others still proceed.',
                  toggle_hint: 'Use custom value',
                  optional: true,
                  control_type: 'text',
                  type: 'string'
                }
              },
              {
                name: 'content_data',
                label: 'Content part of XML request',
                hint: 'Supplies one or more function elements to be ' \
                'executed.  Provide a valid XML with ' \
                '<b>&lt;content&gt;...&lt;/content&gt;</b> ' \
                'tag to send with the request. ' \
                "<a href='https://developer." \
                "intacct.com/web-services/requests/#content-element' " \
                "target='_blank'>Learn more</a>",
                default: "<content>
      <!-- Search call sample -->
      <function controlid=\"UUID-1\">
        <readByQuery>
          <object>LOCATION</object>
          <fields>*</fields>
          <query></query>
          <pagesize>2</pagesize>
          <returnFormat>xml</returnFormat>
        </readByQuery>
      </function>

      <!-- Create call sample -->
      <!--
      <function controlid=\"UUID-2\">
        <create>
           <LOCATION>
             <LOCATIONID>23</LOCATIONID>
             <NAME>HQ</NAME>
           </LOCATION>
        </create>
      </function>
      -->
    </content>",
                optional: false,
                control_type: 'text-area'
              }
            ]
          },
          {
            name: 'request_headers',
            sticky: false,
            extends_schema: true,
            control_type: 'key_value',
            empty_list_title: 'Does this HTTP request require extra headers?',
            empty_list_text: "The header 'x-intacct-xml-request' is sent " \
            "as 'Content-Type' by default.",
            item_label: 'Header',
            type: 'array',
            of: 'object',
            properties: [{ name: 'key' }, { name: 'value' }]
          },
          unless config_fields['response_type'] == 'raw'
            {
              name: 'output',
              label: 'Response body',
              sticky: true,
              extends_schema: true,
              schema_neutral: true,
              control_type: 'schema-designer',
              sample_data_type: 'json_input'
            }
          end,
          {
            name: 'response_headers',
            sticky: false,
            extends_schema: true,
            schema_neutral: true,
            control_type: 'schema-designer',
            sample_data_type: 'json_input'
          },
          {
            name: 'response_type',
            default: 'xml',
            sticky: true,
            extends_schema: true,
            control_type: 'select',
            pick_list: [
              ['XML response', 'xml'], ['JSON response', 'json'],
              ['Raw response', 'raw']
            ]
          },
          unless config_fields['response_type'] == 'raw'
            {
              name: 'surface_errors',
              label: 'Mark failure status in response as error?',
              hint: 'If <b>Yes</b>, the response returned with the failure ' \
              'status will be marked as an unsuccessful action, the error ' \
              'message is surfaced to the job report. If <b>No</b>, the ' \
              'response with failure status will be parsed and captured in ' \
              'the action output without raising any errors. This is useful ' \
              'for capturing the batch action (with multiple functions ' \
              'inside content tag) results.',
              sticky: true,
              control_type: 'select',
              pick_list: [%w[No no], %w[Yes yes]],
              toggle_hint: 'Select from list',
              toggle_field: {
                name: 'surface_errors',
                label: 'Mark failure status in response as error?',
                hint: 'If <b>yes</b>, the response returned with the failure ' \
                'status will be marked as an unsuccessful action, the error ' \
                'message is surfaced to the job report. If <b>no</b>, the ' \
                'response with failure status will be parsed and captured in ' \
                'the action output without raising any errors. This is ' \
                'useful for capturing the batch action (with multiple ' \
                'functions inside content tag) results.',
                toggle_hint: 'Use custom value',
                sticky: true,
                control_type: 'text',
                optional: true,
                type: 'string'
              }
            }
          end,
          if config_fields['response_type'] == 'xml'
            {
              name: 'array_tags',
              label: 'Array tags in XML response',
              hint: 'If you are retrieving multiple locations using ' \
              'readByQuery, you can specify "location" as value. ' \
              'This mainly helps to parse the response XML and group the ' \
              'same tags as array. Provide comma-separated values for ' \
              'specifying multiple array tags.',
              sticky: true
            }
          end
        ].compact
      end
    },

    custom_action_output: {
      fields: lambda do |_connection, config_fields|
        response_body = { name: 'body' }

        [
          if config_fields['response_type'] == 'raw'
            response_body
          elsif (output = config_fields['output'] || '[]')
            output_schema = call('format_schema', parse_json(output))
            if output_schema.dig(0, 'type') == 'array' &&
               output_schema.dig(0, 'details', 'fake_array')
              response_body[:type] = 'array'
              response_body[:properties] = output_schema.dig(0, 'properties')
            else
              response_body[:type] = 'object'
              response_body[:properties] = output_schema
            end

            response_body
          end,
          if (headers = config_fields['response_headers'])
            header_props = parse_json(headers)&.map do |field|
              if field[:name].present?
                field[:name] = field[:name].gsub(/\W/, '_').downcase
              elsif field['name'].present?
                field['name'] = field['name'].gsub(/\W/, '_').downcase
              end
              field
            end

            { name: 'headers', type: 'object', properties: header_props }
          end
        ].compact
      end
    },

    # Custom field
    custom_field: {
      fields: lambda do |_connection, config_fields|
        call('get_custom_fields', config_fields['object'])
      end
    },

    so_n_po_custom_field_out: {
      fields: lambda do |_connection, config_fields|
        config_fields['custom_fields'].split(',')&.map do |field|
          { name: field.strip }
        end || []
      end
    },

    so_n_po_custom_field_update: {
      fields: lambda do |_connection, config_fields|
        custom_fields = config_fields['custom_fields']&.
          split(',')&.
          map do |field|
          { name: field.strip, sticky: true }
        end || []

        [
          {
            name: 'object',
            optional: false,
            control_type: 'select',
            pick_list: 'so_po_objects'
          },
          { name: 'RECORDNO', label: 'Record number', optional: false },
          {
            name: 'custom_fields',
            hint: 'Provide comma-separated custom field names. ' \
            'Find this custom field name as "Integration Name" of the ' \
            'field, on the "Object Definition" page of the corresponding ' \
            'object. E.g., EXTERNAL_ID, SYNC_STATUS',
            optional: false,
            extends_schema: true
          }
        ].concat(custom_fields)
      end
    },

    # Contracts
    contract: {
      fields: lambda do |_connection, _config_fields|
        function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'CONTRACT' }
        }
        response_data = call('get_api_response_data_element', function)

        call('format_schema',
             call('get_object_definition',
                  call('parse_xml_to_hash',
                       'xml' => response_data,
                       'array_fields' => ['Field'])&.
                    dig('Type', 'Fields', 'Field')))
      end
    },

    contract_search: {
      fields: lambda do |_connection, _config_fields|
        function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'CONTRACT' }
        }
        response_data = call('get_api_response_data_element', function)

        fields =
          call('parse_xml_to_hash',
               'xml' => response_data,
               'array_fields' => ['Field'])&.
          dig('Type', 'Fields', 'Field')&.
          select do |field|
            %w[CUSTOMERKEY BILLTOKEY SHIPTOKEY TERMKEY RENEWALMACROKEY RENEWEDCONTRACTKEY
               RENEWCONTRACT_SCHOPKEY RENEWEMAILALERT_SCHOPKEY NONRENEWCONTRACT_SCHOPKEY
               RENEWCUSTOMERALERT_SCHOPKEY PRCLSTKEY MEAPRCLSTKEY
               LOCATIONKEY DEPTKEY CUSTOM_PASSWORD].
              exclude?(field['Name'])
          end&.
          map do |field|
            [field['DisplayLabel'], field['Name']]
          end
        call('query_schema', fields)
      end
    },

    contract_upsert: {
      fields: lambda do |_connection, _config_fields|
        call('contract_upsert_schema')
      end
    },

    contract_create: {
      fields: lambda do |_connection, _config_fields|
        contract_create_schema = call('contract_upsert_schema').
                                 ignored('RECORDNO', 'CONTRACTID', 'LOCATIONID',
                                         'BASECURR', 'CURRENCY', 'EXCHRATETYPE').
                                 concat([
                                          {
                                            name: 'CONTRACTID',
                                            label: 'Contract ID',
                                            hint: 'Required if company does not use ' \
                                                  'auto-numbering.',
                                            sticky: true
                                          },
                                          {
                                            name: 'LOCATIONID',
                                            label: 'Location',
                                            optional: false,
                                            control_type: 'select',
                                            pick_list: 'locations',
                                            toggle_hint: 'Select from list',
                                            toggle_field: {
                                              name: 'LOCATIONID',
                                              label: 'Location ID',
                                              toggle_hint: 'Use custom value',
                                              control_type: 'text',
                                              optional: false,
                                              type: 'string'
                                            }
                                          },
                                          {
                                            name: 'BASECURR',
                                            label: 'Base currency',
                                            hint: 'Required if company is configured for ' \
                                            'multi-currency.',
                                            sticky: true
                                          },
                                          {
                                            name: 'CURRENCY',
                                            label: 'Transaction currency',
                                            hint: 'Required if company is configured for ' \
                                            'multi-currency.',
                                            sticky: true
                                          },
                                          {
                                            name: 'EXCHRATETYPE',
                                            label: 'Exchange rate type',
                                            hint: 'Required if company is configured for ' \
                                                  'multi-currency (Leave blank to ' \
                                                  'use Intacct Daily Rate)',
                                            sticky: true
                                          }
                                        ])

        call('add_required_attribute',
             'object_def' => contract_create_schema,
             'fields' => %w[
               CUSTOMERID NAME BEGINDATE ENDDATE TERMNAME
               BILLINGFREQUENCY
             ])
      end
    },

    contract_update: {
      fields: lambda do |_connection, _config_fields|
        [
          {
            name: 'RECORDNO',
            label: 'Record number',
            hint: 'Required if not using Contract ID',
            sticky: true,
            type: 'integer'
          },
          {
            name: 'CONTRACTID',
            label: 'Contract ID',
            hint: 'Required if not using Record number',
            sticky: true
          }
        ].concat(call('contract_upsert_schema').
          ignored('RECORDNO', 'CONTRACTID', 'STATE'))
      end
    },

    # Contract line
    contract_line: {
      fields: lambda do |_connection, _config_fields|
        function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'CONTRACTDETAIL' }
        }
        response_data = call('get_api_response_data_element', function)

        call('get_object_definition',
             call('parse_xml_to_hash',
                  'xml' => response_data,
                  'array_fields' => ['Field'])&.
               dig('Type', 'Fields', 'Field'))
      end
    },

    contract_line_search: {
      fields: lambda do |_connection, _config_fields|
        function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'CONTRACTDETAIL' }
        }
        response_data = call('get_api_response_data_element', function)

        fields =
          call('parse_xml_to_hash',
               'xml' => response_data,
               'array_fields' => ['Field'])&.
          dig('Type', 'Fields', 'Field')&.
          select do |field|
            %w[SHORTITEMDESC REVENUEPOSTINGTYPE REVENUE2POSTINGTYPE REVPOSTINGCONVERSIONDATE
               REV2POSTINGCONVERSIONDATE CALCULATEDREVENUEPOSTINGTYPE
               CALCULATEDREVENUE2POSTINGTYPE].exclude?(field['Name'])
          end&.
          map do |field|
            [field['DisplayLabel'], field['Name']]
          end
        call('query_schema', fields)
      end
    },

    contract_line_upsert: {
      fields: lambda do |_connection, _config_fields|
        call('contract_line_upsert_schema')
      end
    },

    contract_line_create: {
      fields: lambda do |_connection, _config_fields|
        contract_line_schema = call('contract_line_upsert_schema').
                               ignored('RECORDNO')

        call('add_required_attribute',
             'object_def' => contract_line_schema,
             'fields' => %w[CONTRACTID ITEMID BILLINGMETHOD LOCATIONID])
      end
    },

    contract_line_update: {
      fields: lambda do |_connection, _config_fields|
        call('add_required_attribute',
             'object_def' =>
             call('contract_line_upsert_schema').ignored('CONTRACTID', 'STATE'),
             'fields' => %w[RECORDNO])
      end
    },

    contract_line_hold: {
      fields: lambda do |_connection, _config_fields|
        call('contract_line_hold_schema')
      end
    },

    contract_line_uncancel: {
      fields: lambda do |_connection, _config_fields|
        [
          { name: 'RECORDNO',
            label: 'Record number',
            optional: false,
            type: 'integer',
            control_type: 'integer' }
        ]
      end
    },

    # Contract expense line
    contract_expense: {
      fields: lambda do |_connection, _config_fields|
        function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'CONTRACTEXPENSE' }
        }
        response_data = call('get_api_response_data_element', function)

        call('get_object_definition',
             call('parse_xml_to_hash',
                  'xml' => response_data,
                  'array_fields' => ['Field'])&.
               dig('Type', 'Fields', 'Field'))
      end
    },

    contract_expense_search: {
      fields: lambda do |_connection, _config_fields|
        function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'CONTRACTEXPENSE' }
        }
        response_data = call('get_api_response_data_element', function)

        fields =
          call('parse_xml_to_hash',
               'xml' => response_data,
               'array_fields' => ['Field'])&.
          dig('Type', 'Fields', 'Field')&.
          select { |field| %w[CALCULATEDEXPENSEPOSTINGTYPE LINENO].exclude?(field['Name']) }&.
          map do |field|
            [field['DisplayLabel'], field['Name']]
          end
        call('query_schema', fields)
      end
    },

    # Employee
    employee: {
      fields: lambda do |_connection, _config_fields|
        function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'EMPLOYEE' }
        }
        response_data = call('get_api_response_data_element', function)

        call('format_schema',
             call('get_object_definition',
                  call('parse_xml_to_hash',
                       'xml' => response_data,
                       'array_fields' => ['Field'])&.
                    dig('Type', 'Fields', 'Field')))
      end
    },

    employee_search: {
      fields: lambda do |_connection, _config_fields|
        function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'EMPLOYEE' }
        }
        response_data = call('get_api_response_data_element', function)

        fields =
          call('parse_xml_to_hash',
               'xml' => response_data,
               'array_fields' => ['Field'])&.
          dig('Type', 'Fields', 'Field')&.
          map do |field|
            [field['DisplayLabel'], field['Name']]
          end
        call('query_schema', fields)
      end
    },

    employee_create: {
      fields: lambda do |_connection, _config_fields|
        [
          { name: 'EMPLOYEEID', label: 'Employee ID', sticky: true },
          {
            name: 'PERSONALINFO',
            label: 'Personal info',
            hint: 'Contact info',
            optional: false,
            type: 'object',
            properties: [{
              name: 'CONTACTNAME',
              label: 'Contact name',
              hint: 'Contact name of an existing contact',
              optional: false,
              control_type: 'select',
              pick_list: 'contact_names',
              toggle_hint: 'Select from list',
              toggle_field: {
                name: 'CONTACTNAME',
                label: 'Contact name',
                toggle_hint: 'Use custom value',
                optional: false,
                control_type: 'text',
                type: 'string'
              }
            }]
          },
          {
            name: 'STARTDATE',
            label: 'Start date',
            convert_input: 'convert_date',
            convert_output: 'convert_date',
            type: 'date'
          },
          { name: 'TITLE', label: 'Title' },
          {
            name: 'SSN',
            label: 'Social Security Number',
            hint: 'Do not include dashes.'
          },
          { name: 'EMPLOYEETYPE', label: 'Employee type' },
          {
            name: 'STATUS',
            label: 'Status',
            hint: 'Default: Active',
            control_type: 'select',
            pick_list: 'statuses',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'STATUS',
              label: 'Status',
              hint: 'Allowed values are: active, inactive',
              toggle_hint: 'Use custom value',
              optional: true,
              control_type: 'text',
              type: 'string'
            }
          },
          {
            name: 'BIRTHDATE',
            label: 'Birth date',
            convert_input: 'convert_date',
            convert_output: 'convert_date',
            type: 'date'
          },
          {
            name: 'ENDDATE',
            label: 'End date',
            convert_input: 'convert_date',
            convert_output: 'convert_date',
            type: 'date'
          },
          {
            name: 'TERMINATIONTYPE',
            label: 'Termination type',
            control_type: 'select',
            pick_list: 'termination_types',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'TERMINATIONTYPE',
              label: 'Termination type',
              hint: 'Allowed values are: voluntary, involuntary, deceased, ' \
              'disability, and retired.',
              toggle_hint: 'Use custom value',
              optional: true,
              control_type: 'text',
              type: 'string'
            }
          },
          {
            name: 'SUPERVISORID',
            label: 'Manager',
            control_type: 'select',
            pick_list: 'employees',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'SUPERVISORID',
              label: "Manager's employee ID",
              toggle_hint: 'Use custom value',
              optional: true,
              control_type: 'text',
              type: 'string'
            }
          },
          {
            name: 'GENDER',
            label: 'Gender',
            control_type: 'select',
            pick_list: 'genders',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'GENDER',
              label: 'Gender',
              hint: 'Allowed values are: male, female',
              toggle_hint: 'Use custom value',
              optional: true,
              control_type: 'text',
              type: 'string'
            }
          },
          {
            name: 'DEPARTMENTID',
            label: 'Department',
            control_type: 'select',
            pick_list: 'departments',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'DEPARTMENTID',
              label: 'Department ID',
              toggle_hint: 'Use custom value',
              optional: true,
              control_type: 'text',
              type: 'string'
            }
          },
          {
            name: 'LOCATIONID',
            label: 'Location',
            hint: 'Required only when an employee is created at the ' \
              'top level in a multi-entity, multi-base-currency company.',
            sticky: true,
            control_type: 'select',
            pick_list: 'locations',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'LOCATIONID',
              label: 'Location ID',
              toggle_hint: 'Use custom value',
              optional: true,
              control_type: 'text',
              type: 'string'
            }
          },
          {
            name: 'CLASSID',
            label: 'Class',
            control_type: 'select',
            pick_list: 'classes',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'CLASSID',
              label: 'Class ID',
              toggle_hint: 'Use custom value',
              optional: true,
              control_type: 'text',
              type: 'string'
            }
          },
          {
            name: 'CURRENCY',
            label: 'Currency',
            hint: 'Default currency code'
          },
          { name: 'EARNINGTYPENAME', label: 'Earning type name' },
          {
            name: 'POSTACTUALCOST',
            label: 'Post actual cost',
            hint: 'Default: No',
            control_type: 'checkbox',
            type: 'boolean',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'POSTACTUALCOST',
              label: 'Post actual cost',
              hint: 'Allowed values are: true, false',
              toggle_hint: 'Use custom value',
              optional: true,
              control_type: 'text',
              type: 'boolean'
            }
          },
          { name: 'NAME1099', label: 'Name 1099', hint: 'Form 1099 name' },
          { name: 'FORM1099TYPE', label: 'Form 1099 type' },
          { name: 'FORM1099BOX', label: 'Form 1099 box' },
          {
            name: 'SUPDOCFOLDERNAME',
            label: 'Supporting doc folder name',
            hint: 'Attachment folder name'
          },
          { name: 'PAYMETHODKEY', label: 'Preferred payment method' },
          {
            name: 'PAYMENTNOTIFY',
            label: 'Payment notify',
            hint: 'Send automatic payment notification. Default: No',
            control_type: 'checkbox',
            type: 'boolean',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'PAYMENTNOTIFY',
              label: 'Payment notify',
              hint: 'Allowed values are: true, false',
              toggle_hint: 'Use custom value',
              optional: true,
              control_type: 'text',
              type: 'boolean'
            }
          },
          {
            name: 'MERGEPAYMENTREQ',
            label: 'Merge payment requests',
            hint: 'Default: Yes',
            control_type: 'checkbox',
            type: 'boolean',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'MERGEPAYMENTREQ',
              label: 'Merge payment requests',
              hint: 'Allowed values are: true, false',
              toggle_hint: 'Use custom value',
              optional: true,
              control_type: 'text',
              type: 'boolean'
            }
          },
          {
            name: 'ACHENABLED',
            label: 'ACH enabled',
            hint: 'Default: No',
            control_type: 'checkbox',
            type: 'boolean',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'ACHENABLED',
              label: 'ACH enabled',
              hint: 'Allowed values are: true, false',
              toggle_hint: 'Use custom value',
              optional: true,
              control_type: 'text',
              type: 'boolean'
            }
          },
          { name: 'ACHBANKROUTINGNUMBER', label: 'ACH bank routing number' },
          { name: 'ACHACCOUNTNUMBER', label: 'ACH account number' },
          { name: 'ACHACCOUNTTYPE', label: 'ACH account type' },
          { name: 'ACHREMITTANCETYPE', label: 'ACH remittance type' },
          {
            name: 'customfields',
            label: 'Custom fields/dimensions',
            sticky: true,
            type: 'array',
            of: 'object',
            properties: [{
              name: 'customfield',
              label: 'Custom field/dimension',
              sticky: true,
              type: 'array',
              of: 'object',
              properties: [
                {
                  name: 'customfieldname',
                  label: 'Custom field/dimension name',
                  hint: 'Integration name of the custom field or ' \
                    'custom dimension. Find integration name in object ' \
                    'definition page of the respective object. Prepend ' \
                    "custom dimension with 'GLDIM'; e.g., if the " \
                    'custom dimension is Rating, use ' \
                    "'<b>GLDIM</b>Rating' as integration name here.",
                  sticky: true
                },
                {
                  name: 'customfieldvalue',
                  label: 'Custom field/dimension value',
                  hint: 'The value of custom field or custom dimension',
                  sticky: true
                }
              ]
            }]
          }
        ]
      end
    },

    employee_get: {
      fields: lambda do |_connection, _config_fields|
        [
          {
            name: 'RECORDNO',
            label: 'Record number',
            sticky: true,
            type: 'integer'
          },
          {
            name: 'EMPLOYEEID',
            label: 'Employee',
            sticky: true,
            control_type: 'select',
            pick_list: 'employees',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'EMPLOYEEID',
              label: 'Employee ID',
              toggle_hint: 'Use custom value',
              optional: true,
              control_type: 'text',
              type: 'string'
            }
          },
          {
            name: 'PERSONALINFO',
            label: 'Personal info',
            hint: 'Contact info',
            type: 'object',
            properties: [
              {
                name: 'CONTACTNAME',
                label: 'Contact name',
                hint: 'Contact name of an existing contact'
              },
              { name: 'PRINTAS', label: 'Print as' },
              { name: 'COMPANYNAME', label: 'Company name' },
              {
                name: 'TAXABLE',
                label: 'Taxable',
                control_type: 'checkbox',
                type: 'boolean',
                toggle_hint: 'Select from list',
                toggle_field: {
                  name: 'TAXABLE',
                  label: 'Taxable',
                  toggle_hint: 'Use custom value',
                  optional: true,
                  control_type: 'text',
                  type: 'boolean'
                }
              },
              {
                name: 'TAXGROUP',
                label: 'Tax group',
                hint: 'Contact tax group name'
              },
              { name: 'PREFIX', label: 'Prefix' },
              { name: 'FIRSTNAME', label: 'First name' },
              { name: 'LASTNAME', label: 'Last name' },
              { name: 'INITIAL', label: 'Initial', hint: 'Middle name' },
              {
                name: 'PHONE1',
                label: 'Primary phone number',
                control_type: 'phone'
              },
              {
                name: 'PHONE2',
                label: 'Secondary phone number',
                control_type: 'phone'
              },
              {
                name: 'CELLPHONE',
                label: 'Cellphone',
                hint: 'Cellular phone number',
                control_type: 'phone'
              },
              { name: 'PAGER', label: 'Pager', hint: 'Pager number' },
              { name: 'FAX', label: 'Fax', hint: 'Fax number' },
              {
                name: 'EMAIL1',
                label: 'Primary email address',
                control_type: 'email'
              },
              {
                name: 'EMAIL2',
                label: 'Secondary email address',
                control_type: 'email'
              },
              {
                name: 'URL1',
                label: 'Primary URL',
                control_type: 'url'
              },
              {
                name: 'URL2',
                label: 'Secondary URL',
                control_type: 'url'
              },
              {
                name: 'STATUS',
                label: 'Status',
                control_type: 'select',
                pick_list: 'statuses',
                toggle_hint: 'Select from list',
                toggle_field: {
                  name: 'STATUS',
                  label: 'Status',
                  toggle_hint: 'Use custom value',
                  optional: true,
                  control_type: 'text',
                  type: 'string'
                }
              },
              {
                name: 'MAILADDRESS',
                label: 'Mailing information',
                type: 'object',
                properties: [
                  { name: 'ADDRESS1', label: 'Address line 1' },
                  { name: 'ADDRESS2', label: 'Address line 2' },
                  { name: 'CITY', label: 'City' },
                  { name: 'STATE', label: 'State', hint: 'State/province' },
                  { name: 'ZIP', label: 'Zip', hint: 'Zip/postal code' },
                  { name: 'COUNTRY', label: 'Country' }
                ]
              }
            ]
          },
          {
            name: 'STARTDATE',
            label: 'Start date',
            convert_input: 'convert_date',
            convert_output: 'convert_date',
            type: 'date'
          },
          { name: 'TITLE', label: 'Title', sticky: true },
          {
            name: 'SSN',
            label: 'Social Security Number',
            hint: 'Do not include dashes'
          },
          { name: 'EMPLOYEETYPE', label: 'Employee type' },
          {
            name: 'STATUS',
            label: 'Status',
            control_type: 'select',
            pick_list: 'statuses',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'STATUS',
              label: 'Status',
              toggle_hint: 'Use custom value',
              optional: true,
              control_type: 'text',
              type: 'string'
            }
          },
          {
            name: 'BIRTHDATE',
            label: 'Birth date',
            convert_input: 'convert_date',
            convert_output: 'convert_date',
            type: 'date'
          },
          {
            name: 'ENDDATE',
            label: 'End date',
            convert_input: 'convert_date',
            convert_output: 'convert_date',
            type: 'date'
          },
          {
            name: 'TERMINATIONTYPE',
            label: 'Termination type',
            control_type: 'select',
            pick_list: 'termination_types',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'TERMINATIONTYPE',
              label: 'Termination type',
              toggle_hint: 'Use custom value',
              optional: true,
              control_type: 'text',
              type: 'string'
            }
          },
          {
            name: 'SUPERVISORID',
            label: 'Manager',
            control_type: 'select',
            pick_list: 'employees',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'SUPERVISORID',
              label: "Manager's employee ID",
              toggle_hint: 'Use custom value',
              optional: true,
              control_type: 'text',
              type: 'string'
            }
          },
          {
            name: 'GENDER',
            label: 'Gender',
            control_type: 'select',
            pick_list: 'genders',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'GENDER',
              label: 'Gender',
              toggle_hint: 'Use custom value',
              optional: true,
              control_type: 'text',
              type: 'string'
            }
          },
          {
            name: 'DEPARTMENTID',
            label: 'Department',
            sticky: true,
            control_type: 'select',
            pick_list: 'departments',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'DEPARTMENTID',
              label: 'Department ID',
              toggle_hint: 'Use custom value',
              optional: true,
              control_type: 'text',
              type: 'string'
            }
          },
          {
            name: 'LOCATIONID',
            label: 'Location',
            hint: 'Required only when an employee is created at the ' \
              'top level in a multi-entity, multi-base-currency company.',
            sticky: true,
            control_type: 'select',
            pick_list: 'locations',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'LOCATIONID',
              label: 'Location ID',
              toggle_hint: 'Use custom value',
              optional: true,
              control_type: 'text',
              type: 'string'
            }
          },
          {
            name: 'CLASSID',
            label: 'Class',
            sticky: true,
            control_type: 'select',
            pick_list: 'classes',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'CLASSID',
              label: 'Class ID',
              toggle_hint: 'Use custom value',
              optional: true,
              control_type: 'text',
              type: 'string'
            }
          },
          {
            name: 'CURRENCY',
            label: 'Currency',
            hint: 'Default currency code'
          },
          { name: 'EARNINGTYPENAME', label: 'Earning type name' },
          {
            name: 'POSTACTUALCOST',
            label: 'Post actual cost',
            control_type: 'checkbox',
            type: 'boolean',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'POSTACTUALCOST',
              label: 'Post actual cost',
              toggle_hint: 'Use custom value',
              optional: true,
              control_type: 'text',
              type: 'boolean'
            }
          },
          { name: 'NAME1099', label: 'Name 1099', hint: 'Form 1099 name' },
          { name: 'FORM1099TYPE', label: 'Form 1099 type' },
          { name: 'FORM1099BOX', label: 'Form 1099 box' },
          {
            name: 'SUPDOCFOLDERNAME',
            label: 'Supporting doc folder name',
            hint: 'Attachment folder name'
          },
          { name: 'PAYMETHODKEY', label: 'Preferred payment method' },
          {
            name: 'PAYMENTNOTIFY',
            label: 'Payment notify',
            hint: 'Send automatic payment notification',
            control_type: 'checkbox',
            type: 'boolean',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'PAYMENTNOTIFY',
              label: 'Payment notify',
              toggle_hint: 'Use custom value',
              optional: true,
              control_type: 'text',
              type: 'boolean'
            }
          },
          {
            name: 'MERGEPAYMENTREQ',
            label: 'Merge payment requests',
            control_type: 'checkbox',
            type: 'boolean',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'MERGEPAYMENTREQ',
              label: 'Merge payment requests',
              toggle_hint: 'Use custom value',
              optional: true,
              control_type: 'text',
              type: 'boolean'
            }
          },
          {
            name: 'ACHENABLED',
            label: 'ACH enabled',
            control_type: 'checkbox',
            type: 'boolean',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'ACHENABLED',
              label: 'ACH enabled',
              toggle_hint: 'Use custom value',
              optional: true,
              control_type: 'text',
              type: 'boolean'
            }
          },
          { name: 'ACHBANKROUTINGNUMBER', label: 'ACH bank routing number' },
          { name: 'ACHACCOUNTNUMBER', label: 'ACH account number' },
          { name: 'ACHACCOUNTTYPE', label: 'ACH account type' },
          { name: 'ACHREMITTANCETYPE', label: 'ACH remittance type' },
          {
            name: 'WHENCREATED',
            label: 'Created date',
            parse_output: lambda do |field|
              field&.to_time(format: '%m/%d/%Y %H:%M:%S')
            end,
            type: 'timestamp'
          },
          {
            name: 'WHENMODIFIED',
            label: 'Modified date',
            parse_output: lambda do |field|
              field&.to_time(format: '%m/%d/%Y %H:%M:%S')
            end,
            type: 'timestamp'
          },
          { name: 'CREATEDBY', label: 'Created by' },
          { name: 'MODIFIEDBY', label: 'Modified by' }
        ]
      end
    },

    employee_update: {
      fields: lambda do |_connection, _config_fields|
        [
          {
            name: 'RECORDNO',
            label: 'Record number',
            sticky: true,
            type: 'integer'
          },
          { name: 'EMPLOYEEID', label: 'Employee ID', sticky: true },
          {
            name: 'PERSONALINFO',
            label: 'Personal info',
            hint: 'Contact info',
            type: 'object',
            properties: [{
              name: 'CONTACTNAME',
              label: 'Contact name',
              hint: 'Contact name of an existing contact',
              control_type: 'select',
              pick_list: 'contact_names',
              toggle_hint: 'Select from list',
              toggle_field: {
                name: 'CONTACTNAME',
                label: 'Contact name',
                toggle_hint: 'Use custom value',
                optional: true,
                control_type: 'text',
                type: 'string'
              }
            }]
          },
          {
            name: 'STARTDATE',
            label: 'Start date',
            convert_input: 'convert_date',
            convert_output: 'convert_date',
            type: 'date'
          },
          { name: 'TITLE', label: 'Title', sticky: true },
          {
            name: 'SSN',
            label: 'Social Security Number',
            hint: 'Do not include dashes.'
          },
          { name: 'EMPLOYEETYPE', label: 'Employee type' },
          {
            name: 'STATUS',
            label: 'Status',
            hint: 'Default: Active',
            control_type: 'select',
            pick_list: 'statuses',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'STATUS',
              label: 'Status',
              hint: 'Allowed values are: active, inactive',
              toggle_hint: 'Use custom value',
              optional: true,
              control_type: 'text',
              type: 'string'
            }
          },
          {
            name: 'BIRTHDATE',
            label: 'Birth date',
            convert_input: 'convert_date',
            convert_output: 'convert_date',
            type: 'date'
          },
          {
            name: 'ENDDATE',
            label: 'End date',
            convert_input: 'convert_date',
            convert_output: 'convert_date',
            type: 'date'
          },
          {
            name: 'TERMINATIONTYPE',
            label: 'Termination type',
            control_type: 'select',
            pick_list: 'termination_types',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'TERMINATIONTYPE',
              label: 'Termination type',
              hint: 'Allowed values are: voluntary, involuntary, deceased, ' \
              'disability, and retired.',
              toggle_hint: 'Use custom value',
              optional: true,
              control_type: 'text',
              type: 'string'
            }
          },
          {
            name: 'SUPERVISORID',
            label: 'Manager',
            control_type: 'select',
            pick_list: 'employees',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'SUPERVISORID',
              label: "Manager's employee ID",
              toggle_hint: 'Use custom value',
              optional: true,
              control_type: 'text',
              type: 'string'
            }
          },
          {
            name: 'GENDER',
            label: 'Gender',
            control_type: 'select',
            pick_list: 'genders',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'GENDER',
              label: 'Gender',
              hint: 'Allowed values are: male, female',
              toggle_hint: 'Use custom value',
              optional: true,
              control_type: 'text',
              type: 'string'
            }
          },
          {
            name: 'DEPARTMENTID',
            label: 'Department',
            sticky: true,
            control_type: 'select',
            pick_list: 'departments',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'DEPARTMENTID',
              label: 'Department ID',
              toggle_hint: 'Use custom value',
              optional: true,
              control_type: 'text',
              type: 'string'
            }
          },
          {
            name: 'LOCATIONID',
            label: 'Location',
            hint: 'Required only when an employee is created at the ' \
              'top level in a multi-entity, multi-base-currency company.',
            sticky: true,
            control_type: 'select',
            pick_list: 'locations',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'LOCATIONID',
              label: 'Location ID',
              toggle_hint: 'Use custom value',
              optional: true,
              control_type: 'text',
              type: 'string'
            }
          },
          {
            name: 'CLASSID',
            label: 'Class',
            sticky: true,
            control_type: 'select',
            pick_list: 'classes',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'CLASSID',
              label: 'Class ID',
              toggle_hint: 'Use custom value',
              optional: true,
              control_type: 'text',
              type: 'string'
            }
          },
          {
            name: 'CURRENCY',
            label: 'Currency',
            hint: 'Default currency code'
          },
          { name: 'EARNINGTYPENAME', label: 'Earning type name' },
          {
            name: 'POSTACTUALCOST',
            label: 'Post actual cost',
            hint: 'Default: No',
            control_type: 'checkbox',
            type: 'boolean',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'POSTACTUALCOST',
              label: 'Post actual cost',
              hint: 'Allowed values are: true, false',
              toggle_hint: 'Use custom value',
              optional: true,
              control_type: 'text',
              type: 'boolean'
            }
          },
          { name: 'NAME1099', label: 'Name 1099', hint: 'Form 1099 name' },
          { name: 'FORM1099TYPE', label: 'Form 1099 type' },
          { name: 'FORM1099BOX', label: 'Form 1099 box' },
          {
            name: 'SUPDOCFOLDERNAME',
            label: 'Supporting doc folder name',
            hint: 'Attachment folder name'
          },
          { name: 'PAYMETHODKEY', label: 'Preferred payment method' },
          {
            name: 'PAYMENTNOTIFY',
            label: 'Payment notify',
            hint: 'Send automatic payment notification. Default: No',
            control_type: 'checkbox',
            type: 'boolean',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'PAYMENTNOTIFY',
              label: 'Payment notify',
              hint: 'Allowed values are: true, false',
              toggle_hint: 'Use custom value',
              optional: true,
              control_type: 'text',
              type: 'boolean'
            }
          },
          {
            name: 'MERGEPAYMENTREQ',
            label: 'Merge payment requests',
            hint: 'Default: Yes',
            control_type: 'checkbox',
            type: 'boolean',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'MERGEPAYMENTREQ',
              label: 'Merge payment requests',
              hint: 'Allowed values are: true, false',
              toggle_hint: 'Use custom value',
              optional: true,
              control_type: 'text',
              type: 'boolean'
            }
          },
          {
            name: 'ACHENABLED',
            label: 'ACH enabled',
            hint: 'Default: No',
            control_type: 'checkbox',
            type: 'boolean',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'ACHENABLED',
              label: 'ACH enabled',
              hint: 'Allowed values are: true, false',
              toggle_hint: 'Use custom value',
              optional: true,
              control_type: 'text',
              type: 'boolean'
            }
          },
          { name: 'ACHBANKROUTINGNUMBER', label: 'ACH bank routing number' },
          { name: 'ACHACCOUNTNUMBER', label: 'ACH account number' },
          { name: 'ACHACCOUNTTYPE', label: 'ACH account type' },
          { name: 'ACHREMITTANCETYPE', label: 'ACH remittance type' },
          {
            name: 'customfields',
            label: 'Custom fields/dimensions',
            sticky: true,
            type: 'array',
            of: 'object',
            properties: [{
              name: 'customfield',
              label: 'Custom field/dimension',
              sticky: true,
              type: 'array',
              of: 'object',
              properties: [
                {
                  name: 'customfieldname',
                  label: 'Custom field/dimension name',
                  hint: 'Integration name of the custom field or ' \
                    'custom dimension. Find integration name in object ' \
                    'definition page of the respective object. Prepend ' \
                    "custom dimension with 'GLDIM'; e.g., if the " \
                    'custom dimension is Rating, use ' \
                    "'<b>GLDIM</b>Rating' as integration name here.",
                  sticky: true
                },
                {
                  name: 'customfieldvalue',
                  label: 'Custom field/dimension value',
                  hint: 'The value of custom field or custom dimension',
                  sticky: true
                }
              ]
            }]
          }
        ]
      end
    },

    # Contract MEA Bundle
    contract_mea_bundle: {
      fields: lambda do |_connection, _config_fields|
        function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'CONTRACTMEABUNDLE' }
        }
        response_data = call('get_api_response_data_element', function)

        call('format_schema',
             call('get_object_definition',
                  call('parse_xml_to_hash',
                       'xml' => response_data,
                       'array_fields' => ['Field'])&.
                    dig('Type', 'Fields', 'Field')))
      end
    },

    contract_mea_bundle_create: {
      fields: lambda do |_connection, _config_fields|
        [
          { name: 'CONTRACTID', label: 'Contract ID' },
          { name: 'NAME', label: 'Name' },
          { name: 'DESCRIPTION', label: 'Description' },
          {
            name: 'EFFECTIVEDATE',
            label: 'Effective date',
            control_type: 'date',
            type: 'date'
          },
          {
            name: 'ADJUSTMENTPROCESS',
            label: 'Adjustment process',
            sticky: true,
            control_type: 'select',
            pick_list: 'adjustment_process_types',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'ADJUSTMENTPROCESS',
              label: 'Adjustment process',
              hint: 'Allowed values are: One time, Distributed',
              toggle_hint: 'Use custom value',
              optional: true,
              control_type: 'text',
              type: 'string'
            }
          },
          {
            name: 'TYPE',
            label: 'Type',
            default: 'MEA Bundle',
            control_type: 'select',
            pick_list: [['MEA Bundle', 'MEA Bundle']],
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'TYPE',
              label: 'Type',
              hint: 'Allowed value is: MEA Bundle',
              toggle_hint: 'Use custom value',
              optional: true,
              control_type: 'text',
              type: 'string'
            }
          },
          {
            control_type: 'checkbox',
            label: 'Apply to journal 1',
            toggle_hint: 'Select from option list',
            toggle_field: {
              label: 'Apply to journal 1',
              control_type: 'text',
              toggle_hint: 'Use custom value',
              optional: true,
              type: 'boolean',
              name: 'APPLYTOJOURNAL1'
            },
            type: 'boolean',
            name: 'APPLYTOJOURNAL1'
          },
          {
            control_type: 'checkbox',
            label: 'Apply to journal 2',
            toggle_hint: 'Select from option list',
            toggle_field: {
              label: 'Apply to journal 2',
              control_type: 'text',
              toggle_hint: 'Use custom value',
              optional: true,
              type: 'boolean',
              name: 'APPLYTOJOURNAL2'
            },
            type: 'boolean',
            name: 'APPLYTOJOURNAL2'
          },
          { name: 'COMMENTS', label: 'Comments' },
          {
            name: 'CONTRACTMEABUNDLEENTRIES',
            label: 'Contract MEA bundle entries',
            type: 'array',
            of: 'object',
            properties: [
              {
                name: 'CONTRACTDETAILLINENO',
                label: 'Contract detail line number',
                control_type: 'integer',
                type: 'integer'
              },
              {
                name: 'BUNDLENO',
                label: 'Bundle number',
                control_type: 'integer',
                type: 'integer'
              },
              {
                name: 'MEA_AMOUNT',
                label: 'MEA amount',
                control_type: 'number',
                parse_output: 'float_conversion',
                type: 'number'
              }
            ]
          }
        ]
      end
    },

    contract_mea_bundle_search: {
      fields: lambda do |_connection, _config_fields|
        function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'CONTRACTMEABUNDLE' }
        }
        response_data = call('get_api_response_data_element', function)

        fields =
          call('parse_xml_to_hash',
               'xml' => response_data,
               'array_fields' => ['Field'])&.
          dig('Type', 'Fields', 'Field')&.
          map do |field|
            [field['DisplayLabel'], field['Name']]
          end
        call('query_schema', fields)
      end
    },

    # Customer
    customer: {
      fields: lambda do |_connection, _config_fields|
        function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'CUSTOMER' }
        }
        response_data = call('get_api_response_data_element', function)
        call('format_schema',
             call('get_object_definition',
                  call('parse_xml_to_hash',
                       'xml' => response_data,
                       'array_fields' => ['Field'])&.
                    dig('Type', 'Fields', 'Field')))
      end
    },

    customer_search: {
      fields: lambda do |_connection, _config_fields|
        function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'CUSTOMER' }
        }
        response_data = call('get_api_response_data_element', function)

        fields =
          call('parse_xml_to_hash',
               'xml' => response_data,
               'array_fields' => ['Field'])&.
          dig('Type', 'Fields', 'Field')&.
          reject { |item| %w[ACTIVATIONDATE SUBSCRIPTIONENDDATE].include?(item['Name']) }&.
            map do |field|
              [field['DisplayLabel'], field['Name']]
            end
        call('query_schema', fields)
      end
    },

    customer_create: {
      fields: lambda do |_connection, _config_fields|
        [
          { name: 'CUSTOMERID', label: 'Customer ID', sticky: true },
          { name: 'NAME', label: 'Customer name', optional: false },
          {
            name: 'DISPLAYCONTACT',
            label: 'Contact info',
            optional: false,
            type: 'object',
            properties: [
              { name: 'CONTACTNAME', label: 'Contact name', sticky: true },
              { name: 'PRINTAS', label: 'Print as', optional: false },
              {
                name: 'TAXABLE',
                label: 'Taxable',
                sticky: true,
                hint: 'Default: Yes',
                control_type: 'checkbox',
                toggle_hint: 'Select from list',
                toggle_field: {
                  name: 'TAXABLE',
                  label: 'Taxable',
                  hint: 'Use false for No, true for Yes. (Default: true)',
                  toggle_hint: 'Use custom value',
                  optional: true,
                  control_type: 'text',
                  type: 'string'
                }
              },
              {
                name: 'TAXGROUP',
                label: 'Contact tax group name',
                sticky: true
              },
              {
                name: 'MAILADDRESS',
                label: 'Mail address',
                type: 'object',
                properties: [
                  { name: 'COUNTRY', label: 'Country', sticky: true }
                ]
              }
            ]
          },
          {
            name: 'DELIVERY_OPTIONS',
            label: 'Delivery method',
            hint: 'Use either Print, E-Mail, or Print#~#E-Mail for both. ' \
            'If using E-Mail, the customer contact must have a valid ' \
            'e-mail address.',
            sticky: true
          },
          { name: 'CUSTTYPE', label: 'Customer type ID', sticky: true },
          {
            name: 'ACCOUNTKEY',
            label: 'GL account record number',
            sticky: true
          },
          {
            name: 'customfields',
            label: 'Custom fields/dimensions',
            sticky: true,
            type: 'array',
            of: 'object',
            properties: [{
              name: 'customfield',
              label: 'Custom field/dimension',
              type: 'array',
              of: 'object',
              properties: [
                {
                  name: 'customfieldname',
                  label: 'Custom field/dimension name',
                  hint: 'Integration name of the custom field or ' \
                    'custom dimension. Find integration name in object ' \
                    'definition page of the respective object. Prepend ' \
                    "custom dimension with 'GLDIM'; e.g., if the " \
                    'custom dimension is Rating, use ' \
                    "'<b>GLDIM</b>Rating' as integration name here.",
                  sticky: true
                },
                {
                  name: 'customfieldvalue',
                  label: 'Custom field/dimension value',
                  hint: 'The value of custom field or custom dimension',
                  sticky: true
                }
              ]
            }]
          }
        ]
      end
    },

    customer_batch_create_input: {
      fields: lambda do |_connection, _config_fields|
        function_data = {
          name: 'create',
          optional: false,
          type: 'object',
          properties: [{
            name: 'CUSTOMER',
            label: 'Customer',
            optional: false,
            type: 'object',
            properties: call('customer_create_schema')
          }]
        }

        call('batch_input_schema',
             'function_name' => 'Customers batch',
             'function_data' => function_data)
      end
    },

    customer_batch_create_output: {
      fields: lambda do |_connection, _config_fields|
        call('batch_output_schema',
             'data_prop' => [{
               name: 'customer',
               type: 'object',
               properties: [
                 { name: 'RECORDNO', label: 'Record number' },
                 { name: 'CUSTOMERID', label: 'Customer ID' }
               ]
             }])
      end
    },

    contract_line_batch_create_input: {
      fields: lambda do |_connection, _config_fields|
        function_data = {
          name: 'create',
          optional: false,
          type: 'object',
          properties: [{
            name: 'CONTRACTDETAIL',
            label: 'Contract detail',
            optional: false,
            type: 'object',
            properties: call('contract_line_create_schema')
          }]
        }

        call('batch_input_schema',
             'function_name' => 'Contract lines batch',
             'function_data' => function_data)
      end
    },

    contract_line_batch_create_output: {
      fields: lambda do |_connection, _config_fields|
        call('batch_output_schema',
             'data_prop' => [{
               name: 'contractdetail',
               label: 'Contract lines',
               properties: [{ name: 'RECORDNO', label: 'Record number' }]
             }])
      end
    },

    contract_line_batch_create_or_update_response: {
      fields: lambda do |_connection, _config_fields|
        [
          {
            name: 'operation',
            type: 'object',
            properties: [{
              name: 'result',
              type: 'array',
              of: 'object',
              properties: [
                { name: 'status' },
                { name: 'function' },
                { name: 'controlid', label: 'Control ID' },
                {
                  name: 'data',
                  type: 'object',
                  properties: [{
                    name: 'contractdetail',
                    label: 'Contract lines',
                    type: 'object',
                    properties: [{ name: 'RECORDNO', label: 'Record number' }]
                  }]
                },
                {
                  name: 'errormessage',
                  label: 'Error message',
                  type: 'object',
                  properties: [{
                    name: 'error',
                    type: 'array',
                    of: 'object',
                    properties: [
                      { name: 'errorno', label: 'Error number' },
                      { name: 'description' },
                      { name: 'description2' },
                      { name: 'correction' }
                    ]
                  }]
                }
              ]
            }]
          }
        ]
      end
    },

    # Create & Update GL Entry
    gl_batch: {
      fields: lambda do |_connection, _config_fields|
        call('gl_batch_create_schema')
      end
    },

    gl_batch_create_input: {
      fields: lambda do |_connection, _config_fields|
        function_data = {
          name: 'create',
          optional: false,
          type: 'object',
          properties: [{
            name: 'GLBATCH',
            label: 'GL batch',
            optional: false,
            type: 'object',
            properties: call('gl_batch_create_schema').
              ignored('RECORDNO').
              required('JOURNAL', 'BATCH_DATE', 'BATCH_TITLE', 'ENTRIES')
          }]
        }

        call('batch_input_schema',
             'function_name' => 'Journal entries batch',
             'function_data' => function_data)
      end
    },

    gl_batch_create_output: {
      fields: lambda do |_connection, _config_fields|
        call('batch_output_schema',
             'data_prop' => [{
               name: 'glbatch',
               type: 'object',
               properties: [{ name: 'RECORDNO', label: 'Record number' }]
             }])
      end
    },

    # Invoice
    invoice: {
      fields: lambda do |_connection, _config_fields|
        function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'ARINVOICE' }
        }
        response_data = call('get_api_response_data_element', function)

        call('format_schema',
             call('get_object_definition',
                  call('parse_xml_to_hash',
                       'xml' => response_data,
                       'array_fields' => ['Field'])&.
                    dig('Type', 'Fields', 'Field')))
      end
    },

    invoice_item: {
      fields: lambda do |_connection, _config_fields|
        function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'ARINVOICEITEM' }
        }
        response_data = call('get_api_response_data_element', function)

        call('format_schema',
             call('get_object_definition',
                  call('parse_xml_to_hash',
                       'xml' => response_data,
                       'array_fields' => ['Field'])&.
                    dig('Type', 'Fields', 'Field')))
      end
    },

    invoice_search: {
      fields: lambda do |_connection, _config_fields|
        function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'ARINVOICE' }
        }
        response_data = call('get_api_response_data_element', function)

        fields =
          call('parse_xml_to_hash',
               'xml' => response_data,
               'array_fields' => ['Field'])&.
          dig('Type', 'Fields', 'Field')&.
          reject { |item| %w[ENTITY CUSTENTITY RETAINAGEINVTYPE].include?(item['Name']) }&.
            map do |field|
              [field['DisplayLabel'], field['Name']]
            end
        call('query_schema', fields)
      end
    },

    invoice_create: {
      fields: lambda do |_connection, _config_fields|
        call('invoice_create_schema')
      end
    },

    invoice_create_single: {
      fields: lambda do |_connection, _config_fields|
        [
          {
            name: 'create_invoice',
            optional: false,
            type: 'object',
            properties: call('invoice_create_schema')
          }
        ]
      end
    },

    invoice_batch_create_input: {
      fields: lambda do |_connection, _config_fields|
        function_data = {
          name: 'create_invoice',
          label: 'Create invoice',
          optional: false,
          type: 'object',
          properties: call('invoice_create_schema')
        }

        call('batch_input_schema',
             'function_name' => 'Invoices batch',
             'function_data' => function_data)
      end
    },

    # Item
    item_update: {
      fields: lambda do |_connection, _config_fields|
        [
          {
            name: 'RECORDNO',
            label: 'Record number',
            sticky: true,
            type: 'integer'
          },
          { name: 'ITEMID', label: 'Item ID' },
          { name: 'NAME', label: 'Name', sticky: true },
          {
            name: 'STATUS',
            label: 'Status',
            control_type: 'select',
            sticky: true,
            pick_list: 'statuses',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'STATUS',
              label: 'Status',
              hint: 'Allowed values are: active, inactive',
              toggle_hint: 'Use custom value',
              control_type: 'text',
              sticky: true,
              optional: true,
              type: 'string'
            }
          },
          {
            name: 'customfields',
            label: 'Custom fields',
            sticky: true,
            type: 'object',
            properties: call('get_custom_fields', 'ITEM')
          },
          { name: 'PRODUCTLINEID', label: 'Product line ID' },
          { name: 'EXTENDED_DESCRIPTION', label: 'Extended description' },
          { name: 'PODESCRIPTION', label: 'PO description' },
          { name: 'SODESCRIPTION', label: 'SO description' },
          {
            name: 'UOMGRP',
            label: 'UOM group',
            control_type: 'select',
            sticky: true,
            pick_list: 'uom_groups',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'UOMGRP',
              label: 'UOM group',
              hint: 'Use Area, Count, Duration, Length, Numbers, Time, ' \
               'Volume, or Weight (or an existing custom group name)',
              toggle_hint: 'Use custom value',
              control_type: 'text',
              sticky: true,
              optional: true,
              type: 'string'
            }
          },
          { name: 'NOTE', label: 'Note', sticky: true },
          {
            name: 'SHIP_WEIGHT',
            label: 'Ship weight',
            control_type: 'number',
            type: 'number'
          },
          { name: 'GLGROUP', label: 'GL group' },
          {
            name: 'STANDARD_COST',
            label: 'standard cost',
            control_type: 'number',
            type: 'number'
          },
          {
            name: 'BASEPRICE',
            label: 'Base price',
            control_type: 'number',
            type: 'number'
          },
          {
            name: 'TAXABLE',
            label: 'Taxable',
            control_type: 'checkbox',
            type: 'boolean',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'TAXABLE',
              label: 'Taxable',
              hint: 'Allowed values are: true, false',
              toggle_hint: 'Use custom value',
              control_type: 'text',
              optional: true,
              type: 'boolean'
            }
          },
          {
            name: 'TAXGROUP',
            label: 'Tax group',
            type: 'object',
            properties: [{ name: 'NAME', label: 'Name' }]
          },
          {
            name: 'DEFAULTREVRECTEMPLKEY',
            label: 'Default rev rec template ID'
          },
          { name: 'INCOMEACCTKEY', label: 'Revenue GL account number' },
          { name: 'INVACCTKEY', label: 'Inventory GL account number' },
          { name: 'EXPENSEACCTKEY', label: 'Expense GL account number' },
          { name: 'COGSACCTKEY', label: 'COGS GL account number' },
          { name: 'OFFSETOEGLACCOUNTKEY', label: 'AR GL account number' },
          { name: 'OFFSETPOGLACCOUNTKEY', label: 'AP GL account number' },
          {
            name: 'DEFERREDREVACCTKEY',
            label: 'Deferred revenue GL account number'
          },
          {
            name: 'VSOECATEGORY',
            label: 'VSOE category',
            control_type: 'select',
            pick_list: 'vsoe_categories',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'VSOECATEGORY',
              label: 'VSOE category',
              hint: 'Use Product - Specified, Software, Product - ' \
              'Unspecified, Upgrade - Unspecified, Upgrade - Specified, ' \
              'Services, or Post Contract Support(PCS)',
              toggle_hint: 'Use custom value',
              control_type: 'text',
              optional: true,
              type: 'string'
            }
          },
          {
            name: 'VSOEDLVRSTATUS',
            label: 'VSOE default delivery status',
            control_type: 'select',
            pick_list: 'vsoedlvrs_statuses',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'VSOEDLVRSTATUS',
              label: 'VSOE default delivery status',
              hint: 'Allowed values:  Delivered, Undelivered',
              toggle_hint: 'Use custom value',
              control_type: 'text',
              optional: true,
              type: 'string'
            }
          },
          {
            name: 'VSOEREVDEFSTATUS',
            label: 'VSOE default deferral status',
            control_type: 'select',
            pick_list: 'vsoerevdef_statuses',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'VSOEREVDEFSTATUS',
              label: 'VSOE default deferral status',
              hint: 'Use Defer until item is delivered or Defer bundle until ' \
              'item is delivered',
              toggle_hint: 'Use custom value',
              control_type: 'text',
              optional: true,
              type: 'string'
            }
          },
          {
            name: 'REVPOSTING',
            label: 'Kit revenue posting',
            control_type: 'select',
            pick_list: 'revpostings',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'REVPOSTING',
              label: 'Kit revenue posting',
              hint: 'Allowed values:  Component Level, Kit Level',
              toggle_hint: 'Use custom value',
              control_type: 'text',
              optional: true,
              type: 'string'
            }
          },
          {
            name: 'REVPRINTING',
            label: 'Kit print format',
            control_type: 'select',
            pick_list: 'revprintings',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'REVPRINTING',
              label: 'Kit print format',
              hint: 'Allowed values:  Individual Components, Kit',
              toggle_hint: 'Use custom value',
              control_type: 'text',
              optional: true,
              type: 'string'
            }
          },
          {
            name: 'REVPRINTING',
            label: 'Kit print format',
            hint: 'Use Individual Components or Kit'
          },
          { name: 'SUBSTITUTEID', label: 'Substitute item ID' },
          {
            name: 'ENABLE_SERIALNO',
            label: 'Serial tracking enabled',
            control_type: 'checkbox',
            type: 'boolean',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'ENABLE_SERIALNO',
              label: 'Serial tracking enabled',
              hint: 'Allowed values are: true, false',
              toggle_hint: 'Use custom value',
              control_type: 'text',
              optional: true,
              type: 'boolean'
            }
          },
          { name: 'SERIAL_MASKKEY', label: 'Serial number mask' },
          {
            name: 'ENABLE_LOT_CATEGORY',
            label: 'Lot tracking enabled',
            control_type: 'checkbox',
            type: 'boolean',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'ENABLE_LOT_CATEGORY',
              label: 'Lot tracking enabled',
              hint: 'Allowed values are: true, false',
              toggle_hint: 'Use custom value',
              control_type: 'text',
              optional: true,
              type: 'boolean'
            }
          },
          { name: 'LOT_CATEGORYKEY', label: 'Lot category' },
          {
            name: 'ENABLE_BINS',
            label: 'Bin tracking enabled',
            control_type: 'checkbox',
            type: 'boolean',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'ENABLE_BINS',
              label: 'Bin tracking enabled',
              hint: 'Allowed values are: true, false',
              toggle_hint: 'Use custom value',
              control_type: 'text',
              optional: true,
              type: 'boolean'
            }
          },
          {
            name: 'ENABLE_EXPIRATION',
            label: 'Expiration tracking enabled',
            control_type: 'checkbox',
            type: 'boolean',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'ENABLE_EXPIRATION',
              label: 'Expiration tracking enabled',
              hint: 'Allowed values are: true, false',
              toggle_hint: 'Use custom value',
              control_type: 'text',
              optional: true,
              type: 'boolean'
            }
          },
          { name: 'UPC', label: 'UPC' },
          {
            name: 'INV_PRECISION',
            label: 'Inventory unit cost precision',
            type: 'integer'
          },
          {
            name: 'SO_PRECISION',
            label: 'Sales unit cost precision',
            type: 'integer'
          },
          {
            name: 'PO_PRECISION',
            label: 'Purchasing unit cost precision',
            type: 'integer'
          },
          {
            name: 'ENABLELANDEDCOST',
            label: 'Enable landed costs for Inventory item',
            control_type: 'checkbox',
            type: 'boolean',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'ENABLELANDEDCOST',
              label: 'Enable landed costs for Inventory item',
              hint: 'Allowed values are: true, false',
              toggle_hint: 'Use custom value',
              control_type: 'text',
              optional: true,
              type: 'boolean'
            }
          },
          {
            name: 'LANDEDCOSTINFO',
            label: 'Landed cost info',
            type: 'array',
            of: 'object',
            properties: [{
              name: 'ITEMLANDEDCOST',
              label: 'Item landed cost',
              type: 'object',
              properties: [
                { name: 'ITEMID', label: 'Item ID' },
                {
                  name: 'METHOD',
                  label: 'Landed cost mechanism',
                  control_type: 'select',
                  pick_list: 'methods',
                  toggle_hint: 'Select from list',
                  toggle_field: {
                    name: 'METHOD',
                    label: 'Landed cost mechanism',
                    hint: 'Allowed values:  Volume, Weight, Count',
                    toggle_hint: 'Use custom value',
                    control_type: 'text',
                    optional: true,
                    type: 'string'
                  }
                },
                { name: 'VALUE', label: 'Value' },
                {
                  name: 'ACTIVE',
                  label: 'Active',
                  hint: 'Status. Use "No" for inactive, "Yes" for active.',
                  control_type: 'checkbox',
                  type: 'boolean',
                  toggle_hint: 'Select from list',
                  toggle_field: {
                    name: 'ACTIVE',
                    label: 'Active',
                    hint: 'Allowed values are: true, false',
                    toggle_hint: 'Use custom value',
                    control_type: 'text',
                    optional: true,
                    type: 'boolean'
                  }
                }
              ]
            }]
          },
          {
            name: 'HASSTARTENDDATES',
            label: 'Item has start and end dates',
            control_type: 'checkbox',
            type: 'boolean',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'HASSTARTENDDATES',
              label: 'Item has start and end dates',
              hint: 'Allowed values are: true, false',
              toggle_hint: 'Use custom value',
              control_type: 'text',
              optional: true,
              type: 'boolean'
            }
          },
          {
            name: 'TERMPERIOD',
            label: 'Periods measured in',
            control_type: 'select',
            pick_list: 'termperiods',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'TERMPERIOD',
              label: 'Periods measured in',
              hint: 'Allowed values:  Days, Weeks, Months, Years',
              toggle_hint: 'Use custom value',
              control_type: 'text',
              optional: true,
              type: 'string'
            }
          },
          { name: 'TOTALPERIODS', label: 'Number of periods', type: 'integer' },
          {
            name: 'COMPUTEFORSHORTTERM',
            label: 'Prorate price allowed',
            control_type: 'checkbox',
            type: 'boolean',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'COMPUTEFORSHORTTERM',
              label: 'Prorate price allowed',
              hint: 'Allowed values are: true, false',
              toggle_hint: 'Use custom value',
              control_type: 'text',
              optional: true,
              type: 'boolean'
            }
          },
          { name: 'RENEWALMACROID', label: 'Default renewal macro ID' },
          {
            name: 'ENABLE_REPLENISHMENT',
            label: 'Enable replenishment',
            control_type: 'checkbox',
            type: 'boolean',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'ENABLE_REPLENISHMENT',
              label: 'Enable replenishment',
              hint: 'Allowed values are: true, false',
              toggle_hint: 'Use custom value',
              control_type: 'text',
              optional: true,
              type: 'boolean'
            }
          },
          {
            name: 'DEFAULT_REPLENISHMENT_UOM',
            label: 'Default replenishment UOM'
          },
          { name: 'REPLENISHMENT_METHOD', label: 'Replenishment method' },
          {
            name: 'SAFETY_STOCK',
            label: 'Safety stock',
            control_type: 'integer',
            type: 'integer'
          },
          {
            name: 'MAX_ORDER_QTY',
            label: 'Maximum order quantity',
            control_type: 'integer',
            type: 'integer'
          },
          {
            name: 'REORDER_POINT',
            label: 'Reorder point',
            control_type: 'integer',
            type: 'integer'
          },
          {
            name: 'REORDER_QTY',
            label: 'Reorder quantity',
            control_type: 'integer',
            type: 'integer'
          },
          {
            name: 'WAREHOUSEINFO',
            label: 'WAREHOUSEINFO',
            type: 'object',
            properties: [
              {
                name: 'ITEMWAREHOUSEINFO',
                label: 'Item warehouse info',
                type: 'object',
                properties: [
                  { name: 'WAREHOUSEID', label: 'Warehouse ID' },
                  {
                    name: 'ENABLE_REPLENISHMENT',
                    label: 'Enable replenishment',
                    control_type: 'checkbox',
                    type: 'boolean',
                    toggle_hint: 'Select from list',
                    toggle_field: {
                      name: 'ENABLE_REPLENISHMENT',
                      label: 'Enable replenishment',
                      hint: 'Allowed values are: true, false',
                      toggle_hint: 'Use custom value',
                      control_type: 'text',
                      optional: true,
                      type: 'boolean'
                    }
                  },
                  {
                    name: 'REPLENISHMENT_METHOD',
                    label: 'Replenishment method'
                  },
                  {
                    name: 'SAFETY_STOCK',
                    label: 'Safety stock',
                    control_type: 'integer',
                    type: 'integer'
                  },
                  {
                    name: 'MAX_ORDER_QTY',
                    label: 'Maximum order quantity',
                    control_type: 'integer',
                    type: 'integer'
                  },
                  {
                    name: 'REORDER_POINT',
                    label: 'Reorder point',
                    control_type: 'integer',
                    type: 'integer'
                  },
                  {
                    name: 'REORDER_QTY',
                    label: 'Reorder quantity',
                    control_type: 'integer',
                    type: 'integer'
                  },
                  {
                    name: 'ITEMWAREHOUSEVENDORENTRIES',
                    label: 'Item warehouse vendor entries',
                    type: 'array',
                    of: 'object',
                    properties: [
                      { name: 'VENDORID', label: 'Vendor ID' },
                      {
                        name: 'PREFERRED_VENDOR',
                        label: 'Preferred vendor',
                        control_type: 'checkbox',
                        type: 'boolean',
                        toggle_hint: 'Select from list',
                        toggle_field: {
                          name: 'PREFERRED_VENDOR',
                          label: 'Preferred vendor',
                          hint: 'Allowed values are: true, false',
                          toggle_hint: 'Use custom value',
                          control_type: 'text',
                          optional: true,
                          type: 'boolean'
                        }
                      },
                      { name: 'STOCKNO', label: 'Stock number' },
                      { name: 'LEAD_TIME', label: 'Lead time' },
                      {
                        name: 'FORECAST_DEMAND_IN_LEAD_TIME',
                        label: 'Forecast demand in lead time',
                        type: 'integer'
                      },
                      {
                        name: 'ECONOMIC_ORDER_QTY',
                        label: 'Economic order quantity'
                      },
                      { name: 'MIN_ORDER_QTY', label: 'Min order quantity' },
                      { name: 'UOM', label: 'UOM' }
                    ]
                  }
                ]
              }
            ]
          },
          {
            name: 'VENDORINFO',
            label: 'Vendor info',
            type: 'array',
            of: 'object',
            properties: [{
              name: 'ITEMVENDOR',
              label: 'Item vendor',
              type: 'object',
              properties: [
                { name: 'VENDORID', label: 'Vendor ID' },
                {
                  name: 'PREFERRED_VENDOR',
                  label: 'Preferred vendor',
                  control_type: 'checkbox',
                  type: 'boolean',
                  toggle_hint: 'Select from list',
                  toggle_field: {
                    name: 'PREFERRED_VENDOR',
                    label: 'Preferred vendor',
                    hint: 'Allowed values are: true, false',
                    toggle_hint: 'Use custom value',
                    optional: true,
                    control_type: 'text',
                    type: 'boolean'
                  }
                },
                { name: 'STOCKNO', label: 'Stock number' },
                { name: 'LEAD_TIME', label: 'Lead time' },
                {
                  name: 'FORECAST_DEMAND_IN_LEAD_TIME',
                  label: 'Forecast demand in lead time',
                  type: 'integer'
                },
                {
                  name: 'ECONOMIC_ORDER_QTY',
                  label: 'Economic order quantity'
                },
                { name: 'MIN_ORDER_QTY', label: 'Min order quantity' },
                { name: 'UOM', label: 'UOM' }
              ]
            }]
          },
          { name: 'AUTOPRINTLABEL', label: 'Auto printlabel' }
        ]
      end
    },

    legacy_create_or_update_response: {
      fields: lambda do |_connection, _config_fields|
        [
          { name: 'status' },
          { name: 'function' },
          { name: 'controlid', label: 'Control ID' },
          { name: 'key', label: 'Record key' }
        ]
      end
    },

    legacy_batch_create_or_update_response: {
      fields: lambda do |_connection, _config_fields|
        [{
          name: 'operation',
          type: 'object',
          properties: [{
            name: 'result',
            type: 'array',
            of: 'object',
            properties: [
              { name: 'status' },
              { name: 'function' },
              { name: 'controlid', label: 'Control ID' },
              { name: 'key', label: 'Record key' },
              {
                name: 'errormessage',
                label: 'Error message',
                type: 'object',
                properties: [{
                  name: 'error',
                  type: 'array',
                  of: 'object',
                  properties: [
                    { name: 'errorno', label: 'Error number' },
                    { name: 'description' },
                    { name: 'description2' },
                    { name: 'correction' }
                  ]
                }]
              }
            ]
          }]
        }]
      end
    },

    # Purchase order transaction
    po_txn_header: {
      fields: lambda do |_connection, _config_fields|
        [
          {
            name: '@key',
            label: 'Key',
            hint: 'Document ID of purchase transaction'
          },
          {
            name: 'datecreated',
            label: 'Date created',
            hint: 'Transaction date',
            render_input: lambda do |field|
              if (raw_date = field&.to_date)
                {
                  'year' => raw_date&.strftime('%Y') || '',
                  'month' => raw_date&.strftime('%m') || '',
                  'day' => raw_date&.strftime('%d') || ''
                }
              end
            end,
            type: 'date'
          },
          {
            name: 'dateposted',
            label: 'Date posted',
            hint: 'GL posting date',
            render_input: lambda do |field|
              if (raw_date = field&.to_date)
                {
                  'year' => raw_date&.strftime('%Y') || '',
                  'month' => raw_date&.strftime('%m') || '',
                  'day' => raw_date&.strftime('%d') || ''
                }
              end
            end,
            type: 'date'
          },
          { name: 'referenceno', label: 'Reference number' },
          { name: 'vendordocno', label: 'Vendor document number' },
          { name: 'termname', label: 'Payment term' },
          {
            name: 'datedue',
            label: 'Due date',
            render_input: lambda do |field|
              if (raw_date = field&.to_date)
                {
                  'year' => raw_date&.strftime('%Y') || '',
                  'month' => raw_date&.strftime('%m') || '',
                  'day' => raw_date&.strftime('%d') || ''
                }
              end
            end,
            type: 'date'
          },
          { name: 'message' },
          { name: 'shippingmethod', label: 'Shipping method' },
          {
            name: 'returnto',
            label: 'Return to contact',
            type: 'object',
            properties: [{
              name: 'contactname',
              label: 'Contact name',
              hint: 'Contact name of an existing contact',
              control_type: 'select',
              pick_list: 'contact_names',
              toggle_hint: 'Select from list',
              toggle_field: {
                name: 'contactname',
                label: 'Contact name',
                toggle_hint: 'Use custom value',
                optional: true,
                control_type: 'text',
                type: 'string'
              }
            }]
          },
          {
            name: 'payto',
            label: 'Pay to contact',
            type: 'object',
            properties: [{
              name: 'contactname',
              label: 'Contact name',
              hint: 'Contact name of an existing contact',
              control_type: 'select',
              pick_list: 'contact_names',
              toggle_hint: 'Select from list',
              toggle_field: {
                name: 'contactname',
                label: 'Contact name',
                toggle_hint: 'Use custom value',
                optional: true,
                control_type: 'text',
                type: 'string'
              }
            }]
          },
          {
            name: 'supdocid',
            label: 'Supporting document ID',
            hint: 'Attachments ID'
          },
          { name: 'externalid', label: 'External ID' },
          { name: 'basecurr', label: 'Base currency code' },
          { name: 'currency', hint: 'Transaction currency code' },
          {
            name: 'exchratedate',
            label: 'Exchange rate date',
            render_input: lambda do |field|
              if (raw_date = field&.to_date)
                {
                  'year' => raw_date&.strftime('%Y') || '',
                  'month' => raw_date&.strftime('%m') || '',
                  'day' => raw_date&.strftime('%d') || ''
                }
              end
            end,
            type: 'date'
          },
          {
            name: 'exchratetype',
            label: 'Exchange rate type',
            hint: 'Do not use if exchange rate is set. ' \
              '(Leave blank to use Intacct Daily Rate)'
          },
          {
            name: 'exchrate',
            label: 'Exchange rate',
            hint: 'Do not use if exchange rate type is set.'
          },
          {
            name: 'customfields',
            label: 'Custom fields/dimensions',
            type: 'array',
            of: 'object',
            properties: [{
              name: 'customfield',
              label: 'Custom field/dimension',
              type: 'array',
              of: 'object',
              properties: [
                {
                  name: 'customfieldname',
                  label: 'Custom field/dimension name',
                  hint: 'Integration name of the custom field or ' \
                    'custom dimension. Find integration name in object ' \
                    'definition page of the respective object. Prepend ' \
                    "custom dimension with 'GLDIM'; e.g., if the " \
                    'custom dimension is Rating, use ' \
                    "'<b>GLDIM</b>Rating' as integration name here."
                },
                {
                  name: 'customfieldvalue',
                  label: 'Custom field/dimension value',
                  hint: 'The value of custom field or custom dimension'
                }
              ]
            }]
          },
          {
            name: 'state',
            label: 'State',
            hint: 'Action Draft, Pending or Closed. (Default depends ' \
              'on transaction definition configuration)',
            control_type: 'select',
            pick_list: 'transaction_states',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'state',
              label: 'State',
              toggle_hint: 'Use custom value',
              optional: true,
              control_type: 'text',
              type: 'string'
            }
          }
        ]
      end
    },

    po_txn_transitem: {
      fields: lambda do |_connection, _config_fields|
        [
          {
            name: '@key',
            label: 'Key',
            hint: 'Document ID of purchase transaction'
          },
          {
            name: 'updatepotransitems',
            label: 'Transaction items',
            hint: 'Array to create new line items',
            optional: false,
            type: 'array',
            of: 'object',
            properties: [
              {
                name: 'potransitem',
                label: 'Purchase order line items',
                optional: false,
                type: 'array',
                of: 'object',
                properties: [
                  { name: 'itemid', label: 'Item ID', optional: false },
                  { name: 'itemdesc', label: 'Item description' },
                  {
                    name: 'taxable',
                    hint: 'Customer must be set up for taxable.',
                    control_type: 'checkbox',
                    type: 'boolean',
                    toggle_hint: 'Select from list',
                    toggle_field: {
                      name: 'taxable',
                      label: 'Taxable',
                      toggle_hint: 'Use custom value',
                      optional: true,
                      control_type: 'text',
                      type: 'boolean'
                    }
                  },
                  {
                    name: 'warehouseid',
                    label: 'Warehouse',
                    control_type: 'select',
                    pick_list: 'warehouses',
                    toggle_hint: 'Select from list',
                    toggle_field: {
                      name: 'warehouseid',
                      label: 'Warehouse ID',
                      toggle_hint: 'Use custom value',
                      optional: true,
                      control_type: 'text',
                      type: 'string'
                    }
                  },
                  { name: 'quantity', optional: false, type: 'number' },
                  {
                    name: 'unit',
                    hint: 'Unit of measure to base quantity',
                    sticky: true
                  },
                  { name: 'price', type: 'number', sticky: true },
                  {
                    name: 'sourcelinekey',
                    label: 'Source line key',
                    hint: 'Source line to convert this line from. Use the ' \
                      'RECORDNO of the line from the created from ' \
                      'transaction document.'
                  },
                  {
                    name: 'overridetaxamount',
                    label: 'Override tax amount',
                    control_type: 'number',
                    type: 'number'
                  },
                  {
                    name: 'tax',
                    hint: 'Tax amount',
                    control_type: 'number',
                    type: 'number'
                  },
                  {
                    name: 'locationid',
                    label: 'Location',
                    sticky: true,
                    control_type: 'select',
                    pick_list: 'locations',
                    toggle_hint: 'Select from list',
                    toggle_field: {
                      name: 'locationid',
                      label: 'Location ID',
                      toggle_hint: 'Use custom value',
                      optional: true,
                      control_type: 'text',
                      type: 'string'
                    }
                  },
                  {
                    name: 'departmentid',
                    label: 'Department',
                    control_type: 'select',
                    pick_list: 'departments',
                    toggle_hint: 'Select from list',
                    toggle_field: {
                      name: 'departmentid',
                      label: 'Department ID',
                      toggle_hint: 'Use custom value',
                      optional: true,
                      control_type: 'text',
                      type: 'string'
                    }
                  },
                  { name: 'memo', sticky: true },
                  {
                    name: 'form1099',
                    hint: 'Vendor must be set up for 1099s.',
                    control_type: 'checkbox',
                    type: 'boolean',
                    toggle_hint: 'Select from list',
                    toggle_field: {
                      name: 'form1099',
                      label: 'Form 1099',
                      toggle_hint: 'Use custom value',
                      optional: true,
                      control_type: 'text',
                      type: 'boolean'
                    }
                  },
                  {
                    name: 'customfields',
                    label: 'Custom fields/dimensions',
                    type: 'array',
                    of: 'object',
                    properties: [{
                      name: 'customfield',
                      label: 'Custom field/dimension',
                      type: 'array',
                      of: 'object',
                      properties: [
                        {
                          name: 'customfieldname',
                          label: 'Custom field/dimension name',
                          hint: 'Integration name of the custom field or ' \
                            'custom dimension. Find integration name in ' \
                            'object definition page of the respective ' \
                            "object. Prepend custom dimension with 'GLDIM'; " \
                            'e.g., if the custom dimension is Rating, use ' \
                            "'<b>GLDIM</b>Rating' as integration name here."
                        },
                        {
                          name: 'customfieldvalue',
                          label: 'Custom field/dimension value',
                          hint: 'The value of custom field or custom dimension'
                        }
                      ]
                    }]
                  },
                  {
                    name: 'projectid',
                    label: 'Project',
                    control_type: 'select',
                    pick_list: 'projects',
                    toggle_hint: 'Select from list',
                    toggle_field: {
                      name: 'projectid',
                      label: 'Project ID',
                      toggle_hint: 'Use custom value',
                      optional: true,
                      control_type: 'text',
                      type: 'string'
                    }
                  },
                  { name: 'customerid', label: 'Customer ID' },
                  { name: 'vendorid', label: 'Vendor ID' },
                  {
                    name: 'employeeid',
                    label: 'Employee',
                    control_type: 'select',
                    pick_list: 'employees',
                    toggle_hint: 'Select from list',
                    toggle_field: {
                      name: 'employeeid',
                      label: 'Employee ID',
                      toggle_hint: 'Use custom value',
                      optional: true,
                      control_type: 'text',
                      type: 'string'
                    }
                  },
                  {
                    name: 'classid',
                    label: 'Class',
                    control_type: 'select',
                    pick_list: 'classes',
                    toggle_hint: 'Select from list',
                    toggle_field: {
                      name: 'classid',
                      label: 'Class ID',
                      toggle_hint: 'Use custom value',
                      optional: true,
                      control_type: 'text',
                      type: 'string'
                    }
                  },
                  { name: 'contractid', label: 'Contract ID' },
                  {
                    name: 'billable',
                    control_type: 'checkbox',
                    type: 'boolean',
                    toggle_hint: 'Select from list',
                    toggle_field: {
                      name: 'billable',
                      label: 'Billable',
                      toggle_hint: 'Use custom value',
                      optional: true,
                      control_type: 'text',
                      type: 'boolean'
                    }
                  }
                ]
              }
            ]
          }
        ]
      end
    },

    po_txn_updatepotransitem: {
      fields: lambda do |_connection, _config_fields|
        [
          {
            name: '@key',
            label: 'Key',
            hint: 'Document ID of purchase transaction'
          },
          {
            name: 'updatepotransitems',
            label: 'Transaction items',
            hint: 'Array to update the line items',
            optional: false,
            type: 'array',
            of: 'object',
            properties: [
              {
                name: 'updatepotransitem',
                label: 'Purchase order line items',
                hint: 'Purchase order line items to update',
                optional: false,
                type: 'array',
                of: 'object',
                properties: [
                  {
                    name: '@line_num',
                    label: 'Line number',
                    control_type: 'integer',
                    optional: false,
                    type: 'integer'
                  },
                  { name: 'itemid', label: 'Item ID' },
                  { name: 'itemdesc', label: 'Item description' },
                  {
                    name: 'taxable',
                    hint: 'Customer must be set up for taxable.',
                    control_type: 'checkbox',
                    type: 'boolean',
                    toggle_hint: 'Select from list',
                    toggle_field: {
                      name: 'taxable',
                      label: 'Taxable',
                      toggle_hint: 'Use custom value',
                      optional: true,
                      control_type: 'text',
                      type: 'boolean'
                    }
                  },
                  {
                    name: 'warehouseid',
                    label: 'Warehouse',
                    control_type: 'select',
                    pick_list: 'warehouses',
                    toggle_hint: 'Select from list',
                    toggle_field: {
                      name: 'warehouseid',
                      label: 'Warehouse ID',
                      toggle_hint: 'Use custom value',
                      optional: true,
                      control_type: 'text',
                      type: 'string'
                    }
                  },
                  { name: 'quantity', sticky: true, type: 'number' },
                  {
                    name: 'unit',
                    hint: 'Unit of measure to base quantity',
                    sticky: true
                  },
                  { name: 'price', sticky: true, type: 'number' },
                  {
                    name: 'locationid',
                    label: 'Location',
                    sticky: true,
                    control_type: 'select',
                    pick_list: 'locations',
                    toggle_hint: 'Select from list',
                    toggle_field: {
                      name: 'locationid',
                      label: 'Location ID',
                      toggle_hint: 'Use custom value',
                      optional: true,
                      control_type: 'text',
                      type: 'string'
                    }
                  },
                  {
                    name: 'departmentid',
                    label: 'Department',
                    control_type: 'select',
                    pick_list: 'departments',
                    toggle_hint: 'Select from list',
                    toggle_field: {
                      name: 'departmentid',
                      label: 'Department ID',
                      toggle_hint: 'Use custom value',
                      optional: true,
                      control_type: 'text',
                      type: 'string'
                    }
                  },
                  { name: 'memo', sticky: true },
                  {
                    name: 'customfields',
                    label: 'Custom fields/dimensions',
                    sticky: true,
                    type: 'array',
                    of: 'object',
                    properties: [{
                      name: 'customfield',
                      label: 'Custom field/dimension',
                      type: 'array',
                      of: 'object',
                      properties: [
                        {
                          name: 'customfieldname',
                          label: 'Custom field/dimension name',
                          hint: 'Integration name of the custom field or ' \
                            'custom dimension. Find integration name in ' \
                            'object definition page of the respective ' \
                            "object. Prepend custom dimension with 'GLDIM'; " \
                            'e.g., if the custom dimension is Rating, use ' \
                            "'<b>GLDIM</b>Rating' as integration name here.",
                          sticky: true
                        },
                        {
                          name: 'customfieldvalue',
                          label: 'Custom field/dimension value',
                          hint: 'The value of custom field or custom dimension',
                          sticky: true
                        }
                      ]
                    }]
                  },
                  {
                    name: 'projectid',
                    label: 'Project',
                    control_type: 'select',
                    pick_list: 'projects',
                    toggle_hint: 'Select from list',
                    toggle_field: {
                      name: 'projectid',
                      label: 'Project ID',
                      toggle_hint: 'Use custom value',
                      optional: true,
                      control_type: 'text',
                      type: 'string'
                    }
                  },
                  { name: 'customerid', label: 'Customer ID' },
                  { name: 'vendorid', label: 'Vendor ID' },
                  {
                    name: 'employeeid',
                    label: 'Employee',
                    control_type: 'select',
                    pick_list: 'employees',
                    toggle_hint: 'Select from list',
                    toggle_field: {
                      name: 'employeeid',
                      label: 'Employee ID',
                      toggle_hint: 'Use custom value',
                      optional: true,
                      control_type: 'text',
                      type: 'string'
                    }
                  },
                  {
                    name: 'classid',
                    label: 'Class',
                    control_type: 'select',
                    pick_list: 'classes',
                    toggle_hint: 'Select from list',
                    toggle_field: {
                      name: 'classid',
                      label: 'Class ID',
                      toggle_hint: 'Use custom value',
                      optional: true,
                      control_type: 'text',
                      type: 'string'
                    }
                  },
                  { name: 'contractid', label: 'Contract ID' },
                  {
                    name: 'billable',
                    control_type: 'checkbox',
                    type: 'boolean',
                    toggle_hint: 'Select from list',
                    toggle_field: {
                      name: 'billable',
                      label: 'Billable',
                      toggle_hint: 'Use custom value',
                      optional: true,
                      control_type: 'text',
                      type: 'boolean'
                    }
                  }
                ]
              }
            ]
          }
        ]
      end
    },

    # Statistical GL Entry
    stat_gl_batch: {
      fields: lambda do |_connection, _config_fields|
        [
          {
            name: 'RECORDNO',
            label: 'Record number',
            hint: "Stat journal entry 'Record number' to update",
            type: 'integer'
          },
          {
            name: 'BATCH_DATE',
            label: 'Batch date',
            hint: 'Posting date',
            convert_input: 'convert_date',
            convert_output: 'convert_date',
            type: 'date'
          },
          {
            name: 'BATCH_TITLE',
            label: 'Batch title',
            hint: 'Description of entry'
          },
          {
            name: 'HISTORY_COMMENT',
            label: 'History comment',
            hint: 'Comment added to history for this transaction'
          },
          { name: 'REFERENCENO', label: 'Reference number of transaction' },
          { name: 'SUPDOCID', label: 'Attachments ID' },
          {
            name: 'STATE',
            label: 'State',
            hint: 'State to update the entry to. Posted to post to the GL, ' \
              'otherwise Draft.',
            control_type: 'select',
            pick_list: 'update_gl_entry_states',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'STATE',
              label: 'State',
              toggle_hint: 'Use custom value',
              optional: true,
              control_type: 'text',
              type: 'string'
            }
          },
          {
            name: 'ENTRIES',
            hint: 'Must have at least one line',
            type: 'object',
            properties: [{
              name: 'GLENTRY',
              label: 'GL Entry',
              hint: 'Must have at least one line',
              optional: false,
              type: 'array',
              of: 'object',
              properties: [
                { name: 'DOCUMENT', label: 'Document number' },
                { name: 'ACCOUNTNO', label: 'Account number', optional: false },
                {
                  name: 'TRX_AMOUNT',
                  label: 'Transaction amount',
                  hint: 'Absolute value, relates to Transaction type.',
                  optional: false,
                  control_type: 'number',
                  parse_output: 'float_conversion',
                  type: 'number'
                },
                {
                  name: 'TR_TYPE',
                  label: 'Transaction type',
                  hint: "'Debit' for Increase, otherwise 'Credit' for Decrease",
                  optional: false,
                  control_type: 'select',
                  pick_list: 'tr_types',
                  toggle_hint: 'Select from list',
                  toggle_field: {
                    name: 'TR_TYPE',
                    label: 'Transaction type',
                    toggle_hint: 'Use custom value',
                    optional: false,
                    control_type: 'text',
                    type: 'string'
                  }
                },
                {
                  name: 'DESCRIPTION',
                  label: 'Description',
                  hint: 'Memo. If left blank, set this value to match Batch ' \
                    'title.'
                },
                {
                  name: 'ALLOCATION',
                  label: 'Allocation ID',
                  hint: 'All other dimension elements are ' \
                    'ignored if allocation is set.'
                },
                {
                  name: 'DEPARTMENT',
                  label: 'Department',
                  control_type: 'select',
                  pick_list: 'departments',
                  toggle_hint: 'Select from list',
                  toggle_field: {
                    name: 'DEPARTMENT',
                    label: 'Department ID',
                    toggle_hint: 'Use custom value',
                    optional: true,
                    control_type: 'text',
                    type: 'string'
                  }
                },
                {
                  name: 'LOCATION',
                  label: 'Location',
                  hint: 'Required if multi-entity enabled',
                  sticky: true,
                  control_type: 'select',
                  pick_list: 'locations',
                  toggle_hint: 'Select from list',
                  toggle_field: {
                    name: 'LOCATION',
                    label: 'Location ID',
                    toggle_hint: 'Use custom value',
                    optional: true,
                    control_type: 'text',
                    type: 'string'
                  }
                },
                {
                  name: 'PROJECTID',
                  label: 'Project',
                  control_type: 'select',
                  pick_list: 'projects',
                  toggle_hint: 'Select from list',
                  toggle_field: {
                    name: 'PROJECTID',
                    label: 'Project ID',
                    toggle_hint: 'Use custom value',
                    optional: true,
                    control_type: 'text',
                    type: 'string'
                  }
                },
                {
                  name: 'CUSTOMERID',
                  label: 'Customer',
                  control_type: 'select',
                  pick_list: 'customers',
                  toggle_hint: 'Select from list',
                  toggle_field: {
                    name: 'CUSTOMERID',
                    label: 'Customer ID',
                    toggle_hint: 'Use custom value',
                    optional: true,
                    control_type: 'text',
                    type: 'string'
                  }
                },
                {
                  name: 'VENDORID',
                  label: 'Vendor',
                  control_type: 'select',
                  pick_list: 'vendors',
                  toggle_hint: 'Select from list',
                  toggle_field: {
                    name: 'VENDORID',
                    label: 'Vendor ID',
                    toggle_hint: 'Use custom value',
                    optional: true,
                    control_type: 'text',
                    type: 'string'
                  }
                },
                {
                  name: 'EMPLOYEEID',
                  label: 'Employee',
                  control_type: 'select',
                  pick_list: 'employees',
                  toggle_hint: 'Select from list',
                  toggle_field: {
                    name: 'EMPLOYEEID',
                    label: 'Employee ID',
                    toggle_hint: 'Use custom value',
                    optional: true,
                    control_type: 'text',
                    type: 'string'
                  }
                },
                {
                  name: 'ITEMID',
                  label: 'Item',
                  control_type: 'select',
                  pick_list: 'items',
                  toggle_hint: 'Select from list',
                  toggle_field: {
                    name: 'ITEMID',
                    label: 'Item ID',
                    toggle_hint: 'Use custom value',
                    optional: true,
                    control_type: 'text',
                    type: 'string'
                  }
                },
                {
                  name: 'CLASSID',
                  label: 'Class',
                  control_type: 'select',
                  pick_list: 'classes',
                  toggle_hint: 'Select from list',
                  toggle_field: {
                    name: 'CLASSID',
                    label: 'Class ID',
                    toggle_hint: 'Use custom value',
                    optional: true,
                    control_type: 'text',
                    type: 'string'
                  }
                },
                { name: 'CONTRACTID', label: 'Contract ID' },
                {
                  name: 'WAREHOUSEID',
                  label: 'Warehouse',
                  control_type: 'select',
                  pick_list: 'warehouses',
                  toggle_hint: 'Select from list',
                  toggle_field: {
                    name: 'WAREHOUSEID',
                    label: 'Warehouse ID',
                    toggle_hint: 'Use custom value',
                    optional: true,
                    control_type: 'text',
                    type: 'string'
                  }
                },
                {
                  name: 'customfields',
                  label: 'Custom fields/dimensions',
                  sticky: true,
                  type: 'array',
                  of: 'object',
                  properties: [{
                    name: 'customfield',
                    label: 'Custom field/dimension',
                    type: 'array',
                    of: 'object',
                    properties: [
                      {
                        name: 'customfieldname',
                        label: 'Custom field/dimension name',
                        hint: 'Integration name of the custom field or ' \
                          'custom dimension. Find integration name in object ' \
                          'definition page of the respective object. Prepend ' \
                          "custom dimension with 'GLDIM'; e.g., if the " \
                          'custom dimension is Rating, use ' \
                          "'<b>GLDIM</b>Rating' as integration name here.",
                        sticky: true
                      },
                      {
                        name: 'customfieldvalue',
                        label: 'Custom field/dimension value',
                        hint: 'The value of custom field or custom dimension',
                        sticky: true
                      }
                    ]
                  }]
                }
              ]
            }]
          },
          {
            name: 'customfields',
            label: 'Custom fields/dimensions',
            sticky: true,
            type: 'array',
            of: 'object',
            properties: [{
              name: 'customfield',
              label: 'Custom field/dimension',
              type: 'array',
              of: 'object',
              properties: [
                {
                  name: 'customfieldname',
                  label: 'Custom field/dimension name',
                  hint: 'Integration name of the custom field or ' \
                    'custom dimension. Find integration name in object ' \
                    'definition page of the respective object. Prepend ' \
                    "custom dimension with 'GLDIM'; e.g., if the " \
                    'custom dimension is Rating, use ' \
                    "'<b>GLDIM</b>Rating' as integration name here.",
                  sticky: true
                },
                {
                  name: 'customfieldvalue',
                  label: 'Custom field/dimension value',
                  hint: 'The value of custom field or custom dimension',
                  sticky: true
                }
              ]
            }]
          }
        ]
      end
    },

    # Attachment
    supdoc_create: {
      fields: lambda do |_connection, _config_fields|
        [{
          name: 'attachment',
          optional: false,
          type: 'object',
          properties: [
            {
              name: 'supdocid',
              label: 'Supporting document ID',
              hint: 'Required if company does not have ' \
                'attachment autonumbering configured.',
              sticky: true
            },
            {
              name: 'supdocname',
              label: 'Supporting document name',
              hint: 'Name of attachment',
              optional: false
            },
            {
              name: 'supdocfoldername',
              label: 'Folder name',
              hint: 'Folder to create attachment in',
              optional: false
            },
            { name: 'supdocdescription', label: 'Attachment description' },
            {
              name: 'attachments',
              hint: 'Zero to many attachments',
              sticky: true,
              type: 'array',
              of: 'object',
              properties: [{
                name: 'attachment',
                sticky: true,
                type: 'array',
                of: 'object',
                properties: [
                  {
                    name: 'attachmentname',
                    label: 'Attachment name',
                    hint: 'File name, no period or extension',
                    sticky: true
                  },
                  {
                    name: 'attachmenttype',
                    label: 'Attachment type',
                    hint: 'File extension, no period',
                    sticky: true
                  },
                  {
                    name: 'attachmentdata',
                    label: 'Attachment data',
                    hint: 'Base64-encoded file binary data',
                    sticky: true
                  }
                ]
              }]
            }
          ]
        }]
      end
    },

    supdoc_get: {
      fields: lambda do |_connection, _config_fields|
        [
          {
            name: 'supdocid',
            label: 'Supporting document ID',
            hint: 'Required if company does not have ' \
              'attachment autonumbering configured.',
            sticky: true
          },
          {
            name: 'supdocname',
            label: 'Supporting document name',
            hint: 'Name of attachment'
          },
          {
            name: 'folder',
            label: 'Folder name',
            hint: 'Attachment folder name'
          },
          { name: 'description', label: 'Attachment description' },
          {
            name: 'supdocfoldername',
            label: 'Folder name',
            hint: 'Folder to store attachment in'
          },
          { name: 'supdocdescription', label: 'Attachment description' },
          {
            name: 'attachments',
            type: 'array',
            of: 'object',
            properties: [{
              name: 'attachment',
              hint: 'Zero to many attachments',
              type: 'array',
              of: 'object',
              properties: [
                {
                  name: 'attachmentname',
                  label: 'Attachment name',
                  hint: 'File name, no period or extension',
                  sticky: true
                },
                {
                  name: 'attachmenttype',
                  label: 'Attachment type',
                  hint: 'File extension, no period',
                  sticky: true
                },
                {
                  name: 'attachmentdata',
                  label: 'Attachment data',
                  hint: 'Base64-encoded file binary data',
                  sticky: true
                }
              ]
            }]
          },
          { name: 'creationdate', label: 'Creation date' },
          { name: 'createdby', label: 'Created by' },
          { name: 'lastmodified', label: 'Last modified' },
          { name: 'lastmodifiedby', label: 'Last modified by' }
        ]
      end
    },

    # Attachment folder
    supdocfolder: {
      fields: lambda do |_connection, _config_fields|
        [
          {
            name: 'name',
            label: 'Folder name',
            hint: 'Attachment folder name'
          },
          { name: 'description', label: 'Folder description' },
          {
            name: 'parentfolder',
            label: 'Parent folder name',
            hint: 'Parent attachment folder'
          },
          {
            name: 'supdocfoldername',
            label: 'Folder name',
            hint: 'Attachment folder name'
          },
          { name: 'supdocfolderdescription', label: 'Folder description' },
          {
            name: 'supdocparentfoldername',
            label: 'Parent folder name',
            hint: 'Parent attachment folder'
          },
          { name: 'creationdate', label: 'Creation date' },
          { name: 'createdby', label: 'Created by' },
          { name: 'lastmodified', label: 'Last modified' },
          { name: 'lastmodifiedby', label: 'Last modified by' }
        ]
      end
    },

    update_response: {
      fields: lambda do |_connection, _config_fields|
        [{ name: 'RECORDNO', label: 'Record number' }]
      end
    },

    # Task
    task: {
      fields: lambda do |_connection, _config_fields|
        function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'TASK' }
        }
        response_data = call('get_api_response_data_element', function)
        call('format_schema',
             call('get_object_definition',
                  call('parse_xml_to_hash',
                       'xml' => response_data,
                       'array_fields' => ['Field'])&.
                    dig('Type', 'Fields', 'Field')))
      end
    },

    task_search: {
      fields: lambda do |_connection, _config_fields|
        function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'TASK' }
        }
        response_data = call('get_api_response_data_element', function)

        fields =
          call('parse_xml_to_hash',
               'xml' => response_data,
               'array_fields' => ['Field'])&.
          dig('Type', 'Fields', 'Field')&.
          map do |field|
            [field['DisplayLabel'], field['Name']]
          end
        call('query_schema', fields)
      end
    },

    task_get_output: {
      fields: lambda do |_connection, _config_fields|
        function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'TASK' }
        }
        response_data = call('get_api_response_data_element', function)
        call('format_schema',
             call('get_task_object_definition',
                  call('parse_xml_to_hash',
                       'xml' => response_data,
                       'array_fields' => ['Field'])&.
                    dig('Type', 'Fields', 'Field')))
      end
    },

    task_create: {
      fields: lambda do |_connection, _config_fields|
        [
          { name: 'NAME', label: 'Name', sticky: true },
          { name: 'PROJECTID', label: 'Project', optional: false,
            control_type: 'select', pick_list: 'projects',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'PROJECTID',
              label: 'Project ID',
              toggle_hint: 'Use project ID',
              control_type: 'text',
              type: 'string',
              hint: 'e.g. <b>P0001</b>'
            } },
          { name: 'STANDARDTASKID', label: 'Standard task ID', hint: 'ID of a standard ' \
          'task to use. Provide a value for either Task ID or Standard task ID, but not both.' },
          { name: 'TASKID', label: 'Task ID', hint: 'Task ID that is unique for the ' \
          'given project. Provide a value for either Task ID or Standard task ID, but not both.' },
          { name: 'DESCRIPTION', label: 'Description', sticky: true },
          { name: 'TASKNO', label: 'WBS code' },
          { name: 'TASKSTATUS', label: 'Task status', sticky: true,
            control_type: 'select', pick_list: 'task_statuses',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'TASKSTATUS', label: 'Task status',
              type: 'string', control_type: 'text', optional: true,
              toggle_hint: 'Use custom value',
              hint: 'Allowed values are: <b>Not Started</b>, <b>Planned</b>, ' \
              '<b>In Progress</b>, <b>Completed</b>, <b>On Hold</b>'
            } },
          { name: 'PRODUCTIONUNITDESC', label: 'Production unit description' },
          { name: 'PBEGINDATE', label: 'Planned begin date', sticky: true,
            type: 'date', control_type: 'date' },
          { name: 'PENDDATE', label: 'Planned end date', sticky: true,
            type: 'date', control_type: 'date' },
          { name: 'PARENTKEY', label: 'Parent task record number', type: 'integer' },
          { name: 'CLASSID', label: 'Class',
            control_type: 'select', pick_list: 'classes',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'CLASSID', label: 'Class ID',
              toggle_hint: 'Use class ID', control_type: 'text',
              optional: true, type: 'string'
            } },
          { name: 'ITEMID', label: 'Item ID' },
          { name: 'PRIORITY', label: 'Priority',
            type: 'integer', control_type: 'integer' },
          { name: 'BUDGETQTY', label: 'Planned duration', type: 'number' },
          { name: 'ESTQTY', label: 'Estimated duration', type: 'number' },
          { name: 'STATUS', label: 'Status', control_type: 'select',
            pick_list: 'statuses',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'STATUS', label: 'Status',
              type: 'string', control_type: 'text',
              optional: true,
              toggle_hint: 'Use custom value',
              hint: 'Allowed values are: <b>active</b> or <b>inactive</b> '
            } },
          { name: 'SUPDOCID', label: 'Attachments ID' },
          { name: 'BILLABLE', label: 'Billable', sticky: true,
            type: 'boolean', control_type: 'checkbox',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'BILLABLE', label: 'Billable',
              type: 'string', control_type: 'text', optional: true,
              toggle_hint: 'Use custom value',
              hint: 'Allowed values are: <b>true</b>, <b>false</b>'
            } },
          { name: 'ISMILESTONE', label: 'Is milestone', sticky: true,
            type: 'boolean', control_type: 'checkbox',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'ISMILESTONE', label: 'Is milestone',
              type: 'string', control_type: 'text', optional: true,
              toggle_hint: 'Use custom value',
              hint: 'Allowed values are: <b>true</b>, <b>false</b>'
            } },
          { name: 'UTILIZED', label: 'Utilized', sticky: true,
            type: 'boolean', control_type: 'checkbox',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'UTILIZED', label: 'Utilized',
              type: 'string', control_type: 'text', optional: true,
              toggle_hint: 'Use custom value',
              hint: 'Allowed values are: <b>true</b>, <b>false</b>'
            } }
        ].concat(call('get_custom_fields', 'TASK')).compact
      end
    },

    # Timesheet
    timesheet_create: {
      fields: lambda do |_connection, _config_fields|
        [
          { name: 'EMPLOYEEID', sticky: true, label: 'Employee ID' },
          { name: 'BEGINDATE', type: 'date', control_type: 'date', sticky: true,
            label: 'Begin date',
            convert_input: 'convert_date',
            convert_output: 'convert_date' },
          { name: 'GLPOSTDATE', type: 'date', control_type: 'date',
            convert_input: 'convert_date',
            convert_output: 'convert_date',
            label: 'GL posting date' },
          { name: 'DESCRIPTION', label: 'Description' },
          { name: 'SUPDOCID', label: 'Attachments ID' },
          { name: 'STATE', label: 'State',
            control_type: 'select',
            pick_list: 'timesheet_states',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'STATE',
              type: 'string',
              control_type: 'text',
              optional: true,
              label: 'State',
              toggle_hint: 'Use custom value',
              hint: 'Allowed values are: <b>Draft or Submitted</b>. the default value is <b>' \
                    'Draft</b>'
            } },
          {
            name: 'TIMESHEETENTRIES',
            label: 'Timesheet entries',
            sticky: true,
            type: 'array',
            of: 'object',
            properties: [{
              name: 'TIMESHEETENTRY',
              label: 'Timesheet entry',
              sticky: true,
              type: 'array',
              of: 'object',
              properties: call('timesheet_entry_schema')
            }]
          }
        ].concat(call('get_custom_fields', 'TIMESHEET')).compact
      end
    },

    timesheet: {
      fields: lambda do |_connection, _config_fields|
        function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'TIMESHEET' }
        }
        response_data = call('get_api_response_data_element', function)

        call('get_object_definition',
             call('parse_xml_to_hash',
                  'xml' => response_data,
                  'array_fields' => ['Field'])&.
                dig('Type', 'Fields', 'Field')&.
                reject { |field| field['Name'] == 'LINES#' })&.
                concat([{ name: 'LINES', label: 'Line' }])
      end
    },

    timesheet_search: {
      fields: lambda do |_connection, _config_fields|
        function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'TIMESHEET' }
        }
        response_data = call('get_api_response_data_element', function)

        fields =
          call('parse_xml_to_hash',
               'xml' => response_data,
               'array_fields' => ['Field'])&.
          dig('Type', 'Fields', 'Field')&.
          map do |field|
            [field['DisplayLabel'], field['Name']]
          end
        call('query_schema', fields)
      end
    },

    # Timesheet entry
    timesheet_entry: {
      fields: lambda do |_connection, _config_fields|
        function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'TIMESHEETENTRY' }
        }
        response_data = call('get_api_response_data_element', function)

        call('get_object_definition',
             call('parse_xml_to_hash',
                  'xml' => response_data,
                  'array_fields' => ['Field'])&.
                dig('Type', 'Fields', 'Field'))
      end
    },

    timesheet_entry_search: {
      fields: lambda do |_connection, _config_fields|
        function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'TIMESHEETENTRY' }
        }
        response_data = call('get_api_response_data_element', function)

        fields =
          call('parse_xml_to_hash',
               'xml' => response_data,
               'array_fields' => ['Field'])&.
          dig('Type', 'Fields', 'Field')&.
          map do |field|
            [field['DisplayLabel'], field['Name']]
          end
        call('query_schema', fields)
      end
    },

    # Vendor
    vendor: {
      fields: lambda do |_connection, _config_fields|
        function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'VENDOR' }
        }
        response_data = call('get_api_response_data_element', function)
        call('format_schema',
             call('get_object_definition',
                  call('parse_xml_to_hash',
                       'xml' => response_data,
                       'array_fields' => ['Field'])&.
                    dig('Type', 'Fields', 'Field')))
      end
    },

    vendor_search: {
      fields: lambda do |_connection, _config_fields|
        function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'VENDOR' }
        }
        response_data = call('get_api_response_data_element', function)

        fields =
          call('parse_xml_to_hash',
               'xml' => response_data,
               'array_fields' => ['Field'])&.
          dig('Type', 'Fields', 'Field')&.
          map do |field|
            [field['DisplayLabel'], field['Name']]
          end
        call('query_schema', fields)
      end
    },

    # Order Entry Price List
    order_list_get: {
      fields: lambda do |_connection, _config_fields|
        [
          { name: 'RECORDNO', label: 'Record number',
            type: 'integer' },
          { name: 'PRICELISTID',
            label: 'Price list',
            optional: false,
            control_type: 'select',
            pick_list: 'orderpricelists',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'PRICELISTID',
              label: 'Price list ID',
              toggle_hint: 'Use custom value',
              optional: false,
              control_type: 'text',
              type: 'string'
            } },
          { name: 'ITEMID', label: 'Item ID' },
          { name: 'ITEMNAME', label: 'Item name' },
          { name: 'PRODUCTLINEID', label: 'Product line ID' },
          { name: 'ITEM_LINE', label: 'Item line' },
          { name: 'DATEFROM', label: 'Date from' },
          { name: 'DATETO', label: 'Date to' },
          { name: 'QTYLIMITMIN', label: 'Quantity limit minimum', type: 'integer' },
          { name: 'QTYLIMITMAX', label: 'Quantity limit maximum', type: 'integer' },
          { name: 'VALLIMITMIN', label: 'Value limit minimum' },
          { name: 'VALLIMITMAX', label: 'Value limit maximum' },
          { name: 'QTY_OR_VALUE', label: 'Quantity or Value' },
          { name: 'LIMITWINDOW', label: 'Limit window' },
          { name: 'PERC', label: 'PERC' },
          { name: 'VALUE', label: 'Value', type: 'number' },
          { name: 'VALUETYPE', label: 'Value type' },
          { name: 'FIXED', label: 'Fixed' },
          { name: 'SALE', label: 'Sale' },
          { name: 'STATUS', label: 'Status' },
          { name: 'CURRENCY', label: 'Currency' },
          { name: 'EMPLOYEEKEY', label: 'Employee key' },
          { name: 'EMPLOYEEID', label: 'Employee ID' },
          { name: 'EMPLOYEENAME', label: 'Employee name' }
        ]
      end
    },

    oe_price_list: {
      fields: lambda do |_connection, _config_fields|
        function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'SOPRICELIST' }
        }
        response_data = call('get_api_response_data_element', function)

        call('format_schema',
             call('get_object_definition',
                  call('parse_xml_to_hash',
                       'xml' => response_data,
                       'array_fields' => ['Field'])&.
                    dig('Type', 'Fields', 'Field')))
      end
    },

    oe_price_list_search: {
      fields: lambda do |_connection, _config_fields|
        function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'SOPRICELIST' }
        }
        response_data = call('get_api_response_data_element', function)

        fields =
          call('parse_xml_to_hash',
               'xml' => response_data,
               'array_fields' => ['Field'])&.
          dig('Type', 'Fields', 'Field')&.
          map do |field|
            [field['DisplayLabel'], field['Name']]
          end
        call('query_schema', fields)
      end
    },

    purchase_list_get: {
      fields: lambda do |_connection, _config_fields|
        [
          { name: 'RECORDNO', label: 'Record number',
            type: 'integer' },
          { name: 'PRICELISTID',
            label: 'Price list',
            optional: false,
            control_type: 'select',
            pick_list: 'purchasepricelists',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'PRICELISTID',
              label: 'Price list ID',
              toggle_hint: 'Use custom value',
              optional: false,
              control_type: 'text',
              type: 'string'
            } },
          { name: 'ITEMID', label: 'Item ID' },
          { name: 'ITEMNAME', label: 'Item name' },
          { name: 'PRODUCTLINEID', label: 'Product line ID' },
          { name: 'ITEM_LINE', label: 'Item line' },
          { name: 'DATEFROM', label: 'Date from' },
          { name: 'DATETO', label: 'Date to' },
          { name: 'QTYLIMITMIN', label: 'Quantity limit minimum', type: 'integer' },
          { name: 'QTYLIMITMAX', label: 'Quantity limit maximum', type: 'integer' },
          { name: 'VALLIMITMIN', label: 'Value limit minimum' },
          { name: 'VALLIMITMAX', label: 'Value limit maximum' },
          { name: 'QTY_OR_VALUE', label: 'Quantity or Value' },
          { name: 'LIMITWINDOW', label: 'Limit window' },
          { name: 'PERC', label: 'PERC' },
          { name: 'VALUE', label: 'Value', type: 'number' },
          { name: 'VALUETYPE', label: 'Value type' },
          { name: 'FIXED', label: 'Fixed' },
          { name: 'SALE', label: 'Sale' },
          { name: 'STATUS', label: 'Status' },
          { name: 'CURRENCY', label: 'Currency' },
          { name: 'EMPLOYEEKEY', label: 'Employee key' },
          { name: 'EMPLOYEEID', label: 'Employee ID' },
          { name: 'EMPLOYEENAME', label: 'Employee name' }
        ]
      end
    },

    purchase_list_search: {
      fields: lambda do |_connection, _config_fields|
        function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'POPRICELIST' }
        }
        response_data = call('get_api_response_data_element', function)

        fields =
          call('parse_xml_to_hash',
               'xml' => response_data,
               'array_fields' => ['Field'])&.
          dig('Type', 'Fields', 'Field')&.
          map do |field|
            [field['DisplayLabel'], field['Name']]
          end
        call('query_schema', fields)
      end
    },

    purchase_price_list: {
      fields: lambda do |_connection, _config_fields|
        function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'POPRICELIST' }
        }
        response_data = call('get_api_response_data_element', function)

        call('format_schema',
             call('get_object_definition',
                  call('parse_xml_to_hash',
                       'xml' => response_data,
                       'array_fields' => ['Field'])&.
                    dig('Type', 'Fields', 'Field')))
      end
    },

    # Purchasing transaction
    po_document: {
      fields: lambda do |_connection, _config_fields|
        function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'PODOCUMENT' }
        }
        response_data = call('get_api_response_data_element', function)
        call('format_schema',
             call('get_object_definition',
                  call('parse_xml_to_hash',
                       'xml' => response_data,
                       'array_fields' => ['Field'])&.
                    dig('Type', 'Fields', 'Field')))
      end
    },

    po_document_search: {
      fields: lambda do |_connection, _config_fields|
        function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'PODOCUMENT' }
        }
        response_data = call('get_api_response_data_element', function)

        fields =
          call('parse_xml_to_hash',
               'xml' => response_data,
               'array_fields' => ['Field'])&.
          dig('Type', 'Fields', 'Field')&.
          reject { |item| %w[ENABLEDOCCHANGE].include?(item['Name']) }&.
            map do |field|
              [field['DisplayLabel'], field['Name']]
            end
        call('query_schema', fields)
      end
    },

    # Account
    account: {
      fields: lambda do |_connection, _config_fields|
        function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'GLACCOUNT' }
        }
        response_data = call('get_api_response_data_element', function)
        call('format_schema',
             call('get_object_definition',
                  call('parse_xml_to_hash',
                       'xml' => response_data,
                       'array_fields' => ['Field'])&.
                    dig('Type', 'Fields', 'Field')))
      end
    },

    account_search: {
      fields: lambda do |_connection, _config_fields|
        function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'GLACCOUNT' }
        }
        response_data = call('get_api_response_data_element', function)

        fields =
          call('parse_xml_to_hash',
               'xml' => response_data,
               'array_fields' => ['Field'])&.
          dig('Type', 'Fields', 'Field')&.
          map do |field|
            [field['DisplayLabel'], field['Name']]
          end
        call('query_schema', fields)
      end
    },

    # Location
    location: {
      fields: lambda do |_connection, _config_fields|
        function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'LOCATION' }
        }
        response_data = call('get_api_response_data_element', function)
        call('format_schema',
             call('get_object_definition',
                  call('parse_xml_to_hash',
                       'xml' => response_data,
                       'array_fields' => ['Field'])&.
                    dig('Type', 'Fields', 'Field')))
      end
    },

    location_search: {
      fields: lambda do |_connection, _config_fields|
        function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'LOCATION' }
        }
        response_data = call('get_api_response_data_element', function)

        fields =
          call('parse_xml_to_hash',
               'xml' => response_data,
               'array_fields' => ['Field'])&.
          dig('Type', 'Fields', 'Field')&.
          map do |field|
            [field['DisplayLabel'], field['Name']]
          end
        call('query_schema', fields)
      end
    }
  },

  actions: {
    # Create AR Adjustment
    create_ar_adjustment: {
      title: 'Create AR adjustment',
      description: "Create <span class='provider'>AR adjustment</span> in " \
      "<span class='provider'>Sage Intacct (Custom)</span>",
      help: 'Custom fields are supported (at line item) in this action.',

      execute: lambda do |_connection, input, input_schema, _output_schema|
        function = call('format_input_to_match_schema',
                        'schema' => input_schema,
                        'input' => input).merge('@controlid' => 'testControlId')
        response_data = call('get_api_response_result_element', function)

        call('parse_xml_to_hash',
             'xml' => response_data,
             'array_fields' => []) || {}
      end,

      input_fields: lambda do |object_definitions|
        object_definitions['ar_adjustment_create']
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['legacy_create_or_update_response']
      end,

      sample_output: lambda do |_connection, _input|
        {
          status: 'success',
          function: 'create_aradjustment',
          controlid: 'testControlId',
          key: 1234
        }
      end
    },

    create_ar_adjustments_in_batch: {
      title: 'Create AR adjustments in batch',
      description: "Create <span class='provider'>AR adjustments</span> in " \
      "a batch in <span class='provider'>Sage Intacct (Custom)</span>",
      help: 'Custom fields are supported (at line item) in this action. ' \
      'Provide a list of records to be created as the input. The maximum ' \
      'number of AR adjustments in a batch is 100.',

      execute: lambda do |connection, input, input_schema, _output_schema|
        input = call('format_input_to_match_schema',
                     'schema' => input_schema,
                     'input' => call('deep_compact', input))
        function = input.dig('operation_element', 'function')
        if (batch_len = function&.length || 0) > 100
          error('The batch size limit for the action is 100. ' \
            "But the current batch has got #{batch_len} AR adjustments.")
        end
        payload = {
          'control' => input['control_element'] || {},
          'operation' => {
            '@transaction' => input.dig('operation_element', 'transaction'),
            'authentication' => {},
            'content' => { 'function' => function }.compact
          }.compact
        }

        call('get_api_response_element',
             'connection' => connection,
             'payload' => payload)
      end,

      input_fields: lambda do |object_definitions|
        object_definitions['ar_adjustments_batch_create_input']
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['legacy_batch_create_or_update_response']
      end,

      sample_output: lambda do |_connection, _input|
        {
          operation: {
            result: [{
              status: 'success',
              function: 'create_aradjustment',
              controlid: 'ID-007',
              key: '1234',
              errormessage: {
                error: [{
                  errorno: 'BL01001973',
                  description2: 'Currently, we can&#039;t create the ' \
                  'transaction',
                  correction: 'Check the transaction for errors or ' \
                  'inconsistencies, then try again.'
                }]
              }
            }]
          }
        }
      end
    },

    # AR Payment
    search_ar_payments_query: {
      title: 'Search AR payments',
      description: "Search <span class='provider'>AR payments</span> in " \
      "<span class='provider'>Sage Intacct (Custom)</span>",
      help: 'Search will return results that match all your search criteria. ' \
      'Returns a maximum of 2000 records.',

      execute: lambda do |_connection, input|
        field_function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'ARPYMT' }
        }
        get_fields_response = call('get_api_response_data_element', field_function)
        fields =
          call('parse_xml_to_hash',
               'xml' => get_fields_response,
               'array_fields' => ['Field'])&.
          dig('Type', 'Fields', 'Field')&.pluck('Name')&.
          reject { |name| %w[CUSTENTITY].include?(name) }
        select_fields =  { 'field' => input['fields']&.split(',') || fields }
        filter_condition = input['filter_condition'] || 'and'
        query =
          if input['filters'].present?
            if input['filters'].size > 1
              {
                filter_condition =>
                  input['filters']&.map do |filter|
                    { filter['operator'] => { 'field' => filter['field'],
                                              'value' => filter['value']&.split(',') } }
                  end&.each_with_object({}) do |hash, object|
                    hash.each { |key, value| (object[key] ||= []) << value }
                  end
              }
            elsif input['filters'].size == 1
              input['filters']&.map do |filter|
                { filter['operator'] => { 'field' => filter['field'],
                                          'value' => filter['value']&.split(',') } }
              end&.first
            end
          end
        orderby = if input['ordering'].present?
                    { 'order' => { 'field' => input['ordering']['sort_field'],
                                   input['ordering']['sort_order'] => '' } }
                  end
        function = {
          '@controlid' => 'testControlId',
          'query' => {
            'object' => 'ARPYMT',
            'select' => select_fields,
            'filter' => query,
            'orderby' => orderby,
            'options' => input['options'],
            'pagesize' => input['pagesize'] || 100,
            'offset' => input['offset'] || 0
          }.compact
        }
        response_data = call('get_api_response_data_element', function)

        {
          ar_payments: call('format_response',
                            call('parse_xml_to_hash',
                                 'xml' => response_data,
                                 'array_fields' => ['ARPYMT'])&.
                            []('ARPYMT')) || []
        }
      end,

      input_fields: ->(object_definitions) { object_definitions['ar_payment_search'] },

      output_fields: lambda do |object_definitions|
        [{
          name: 'ar_payments',
          label: 'AR payments',
          type: 'array',
          of: 'object',
          properties: object_definitions['ar_payment']
        }]
      end,

      sample_output: lambda do |_connection, _input|
        field_function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'ARPYMT' }
        }
        get_fields_response = call('get_api_response_data_element', field_function)
        fields =
          call('parse_xml_to_hash',
               'xml' => get_fields_response,
               'array_fields' => ['Field'])&.
          dig('Type', 'Fields', 'Field')&.pluck('Name')&.
          reject { |name| %w[CUSTENTITY].include?(name) }
        function = {
          '@controlid' => 'testControlId',
          'query' => {
            'object' => 'ARPYMT',
            'select' => { 'field' => fields },
            'pagesize' => 1
          }.compact
        }
        response_data = call('get_api_response_data_element', function)

        {
          ar_payments: call('format_response',
                            call('parse_xml_to_hash',
                                 'xml' => response_data,
                                 'array_fields' => ['ARPYMT'])&.
                            []('ARPYMT')) || []
        }
      end
    },

    create_ar_payment: {
      title: 'Create AR payment',
      description: "Create <span class='provider'>AR payment</span> in " \
      "<span class='provider'>Sage Intacct (Custom)</span>",

      execute: lambda do |_connection, input, input_schema, _output_schema|
        function = call('format_input_to_match_schema',
                        'schema' => input_schema,
                        'input' => input).merge('@controlid' => 'testControlId')
        response_data = call('get_api_response_result_element', function)

        call('parse_xml_to_hash',
             'xml' => response_data,
             'array_fields' => []) || {}
      end,

      input_fields: lambda do |object_definitions|
        {
          name: 'create_arpayment',
          label: 'Create AR payment',
          optional: false,
          type: 'object',
          properties: object_definitions['ar_payment_create']
        }
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['legacy_create_or_update_response']
      end,

      sample_output: lambda do |_connection, _input|
        {
          status: 'success',
          function: 'create_arpayment',
          controlid: 'testControlId',
          key: 1234
        }
      end
    },

    create_ar_payments_in_batch: {
      title: 'Create AR payments in batch',
      description: "Create <span class='provider'>AR payments</span> in " \
      "a batch in <span class='provider'>Sage Intacct (Custom)</span>",
      help: 'Provide a list of records to be created as the input. ' \
      'The maximum number of AR payments in a batch is 100.',

      execute: lambda do |connection, input, input_schema, _output_schema|
        input = call('format_input_to_match_schema',
                     'schema' => input_schema,
                     'input' => call('deep_compact', input))
        function = input.dig('operation_element', 'function')
        if (batch_len = function&.length || 0) > 100
          error('The batch size limit for the action is 100. ' \
            "But the current batch has got #{batch_len} AR payments.")
        end
        payload = {
          'control' => input['control_element'] || {},
          'operation' => {
            '@transaction' => input.dig('operation_element', 'transaction'),
            'authentication' => {},
            'content' => { 'function' => function }.compact
          }.compact
        }

        call('get_api_response_element',
             'connection' => connection,
             'payload' => payload)
      end,

      input_fields: lambda do |object_definitions|
        object_definitions['ar_payments_batch_create_input']
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['legacy_batch_create_or_update_response']
      end,

      sample_output: lambda do |_connection, _input|
        {
          operation: {
            result: [{
              status: 'success',
              function: 'create_arpayment',
              controlid: 'ID-007',
              key: '1234',
              errormessage: {
                error: [{
                  errorno: 'BL01001973',
                  description2: 'Currently, we can&#039;t create the ' \
                  'transaction',
                  correction: 'Check the transaction for errors or ' \
                  'inconsistencies, then try again.'
                }]
              }
            }]
          }
        }
      end
    },

    # Bank feed
    create_bank_feed: {
      description: "Create <span class='provider'>bank feed</span> in " \
      "<span class='provider'>Sage Intacct (Custom)</span>",

      input_fields: lambda do |object_definitions|
        object_definitions['bank_feed_create']
      end,

      execute: lambda do |_connection, input|
        function = {
          '@controlid' => 'testControlId',
          'create' => { 'BANKACCTTXNFEED' => input }
        }
        response_data = call('get_api_response_data_element', function)

        call('parse_xml_to_hash',
             'xml' => response_data,
             'array_fields' => ['bankaccttxnfeed'])&.
          dig('bankaccttxnfeed', 0) || {}
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['bank_feed'].only('RECORDNO')
      end,

      sample_output: ->(_connection, _input) { { 'RECORDNO' => 1234 } }
    },

    search_bank_feed_entries: {
      description: "Search <span class='provider'>bank feed entries</span> " \
      "in <span class='provider'>Sage Intacct (Custom)</span>",

      input_fields: lambda do |object_definitions|
        object_definitions['bank_feed'].
          only('RECORDNO', 'FINANCIALENTITY', 'FINANCIALENTITYNAME',
               'DESCRIPTION')
      end,

      execute: lambda do |_connection, input|
        query = call('format_payload', input)&.
                map { |key, value| "#{key} = '#{value}'" }&.
                smart_join(' and ') || ''
        function = {
          '@controlid' => 'testControlId',
          'readByQuery' => {
            'object' => 'BANKACCTTXNRECORD',
            'fields' => '*',
            'query' => query,
            'pagesize' => '100'
          }
        }
        response_data = call('get_api_response_data_element', function)

        {
          bank_feeds: call('format_response',
                           call('parse_xml_to_hash',
                                'xml' => response_data,
                                'array_fields' => ['bankaccttxnrecord'])&.
                             []('bankaccttxnrecord')) || []
        }
      end,

      output_fields: lambda do |object_definitions|
        [{
          name: 'bank_feeds',
          type: 'array',
          of: 'object',
          properties: object_definitions['bank_feed']
        }]
      end,

      sample_output: lambda do |_connection, _input|
        function = {
          '@controlid' => 'testControlId',
          'readByQuery' => {
            'object' => 'BANKACCTTXNRECORD',
            'fields' => '*',
            'query' => '',
            'pagesize' => '1'
          }
        }
        response_data = call('get_api_response_data_element', function)

        {
          bank_feeds: call('format_response',
                           call('parse_xml_to_hash',
                                'xml' => response_data,
                                'array_fields' => ['bankaccttxnrecord'])&.
                             []('bankaccttxnrecord')) || []
        }
      end
    },

    # Custom action
    custom_action: {
      subtitle: 'Build your own Sage Intacct action with an ' \
      'HTTP request',

      description: lambda do |object_value, _object_label|
        "<span class='provider'>" \
        "#{object_value[:action_name] || 'Custom action'}</span> in " \
        "<span class='provider'>Sage Intacct (Custom)</span>"
      end,

      help: {
        body: 'Build your own Sage Intacct action with a HTTP ' \
        'request. The request will be authorized with your ' \
        'Sage Intacct connection.',
        learn_more_url: 'https://developer.intacct.com/web-services/requests/',
        learn_more_text: 'Sage Intacct API documentation'
      },

      input_fields: lambda do |object_definitions|
        object_definitions['custom_action_input']
      end,

      execute: lambda do |connection, input|
        content_data = if (content =
                             input.dig('operation_element', 'content_data'))
                         # validate if content contains valid XML
                         if call('validate_xml_string', content)
                           content.from_xml
                         else
                           error('Content data is not a valid XML')
                         end
                       end || {}
        request_headers = input['request_headers']&.
          each_with_object({}) do |item, hash|
            hash[item['key']] = item['value']
          end || {}
        payload = {
          'control' => input['control_element'] || {},
          'operation' => {
            '@transaction' => input.dig('operation_element', 'transaction'),
            'authentication' => {},
            'content' => content_data['content']
          }.compact
        }.compact

        request =
          post(call('get_endpoint_url', connection), payload).
          headers(request_headers)

        response =
          if input['response_type'] == 'xml'
            request.format_xml('request')
          else
            request.request_format_xml('request').response_format_raw
          end.
          after_error_response(/.*/) do |code, body, headers, message|
            error({ code: code, message: message, body: body, headers: headers }.
              to_json)
          end

        response.after_response do |_code, res_body, res_headers|
          body =
            if !res_body.is_a?(String) && input['response_type'] == 'xml'
              # scenario#1 XML Obj
              response = call('validate_intacct_response_auth_error', res_body)
              response =
                call('parse_xml_to_hash',
                     'xml' => response,
                     'array_fields' =>
                     %w[result error data].
                     concat(input['array_tags']&.
                       gsub(/\s+/, '')&.
                       split(',') || [])) || {}
              if input['surface_errors'] == 'yes'
                result = response&.dig('operation', 'result') || {}
                if result.pluck('status').include?('failure') ||
                   result.pluck('status').include?('aborted')
                  error(result&.pluck('errormessage')&.to_json)
                end
              end

              response
            elsif input['response_type'] == 'json'
              # scenario#2 Raw -> XML, JSON, CSV
              if call('validate_intacct_xml_response_string', res_body)
                res_xml_obj = res_body.from_xml
                response = call('validate_intacct_response_auth_error',
                                res_xml_obj)
                error_res = call('parse_xml_to_hash',
                                 'xml' => response,
                                 'array_fields' => %w[result error])
                error(error_res) if input['surface_errors'] == 'yes'

                error_res
              else
                # TODO: validate JSON string before parse_json()
                parse_json(res_body)
              end
            else
              res_body
            end

          { body: call('format_response', body), headers: res_headers }
        end
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['custom_action_output']
      end
    },

    # Custom field
    get_custom_fields: {
      description: "Get <span class='provider'>custom fields</span> of " \
      "an object in <span class='provider'>Sage Intacct (Custom)</span>",
      help: 'This action will inspect the object schema and populates ' \
      'the custom fields in the app data section only if the custom field ' \
      'exists for the selected object.',

      config_fields: [{
        name: 'object',
        optional: false,
        control_type: 'select',
        pick_list: 'standard_objects'
      }],

      input_fields: lambda do |_object_definitions|
        [{ name: 'RECORDNO', label: 'Record number', optional: false }]
      end,

      execute: lambda do |_connection, input|
        function = {
          '@controlid' => 'testControlId',
          'read' => {
            'object' => input['object'],
            'fields' => '*',
            'keys' => input['RECORDNO']
          }
        }
        response_data = call('get_api_response_data_element', function)
        call('parse_xml_to_hash',
             'xml' => response_data,
             'array_fields' => [])&.[](input['object'])
      end,

      output_fields: lambda do |object_definitions|
        [{ name: 'RECORDNO', label: 'Record number' }].
          concat(object_definitions['custom_field'])
      end,

      sample_output: ->(_connection, _input) { { 'RECORDNO' => 1234 } }
    },

    update_custom_fields: {
      description: "Update <span class='provider'>custom fields</span> " \
      "of an object in <span class='provider'>Sage Intacct (Custom)</span>",
      help: 'This action will inspect the object schema and populates ' \
      'the custom fields as input fields, only if the custom field ' \
      'exists for the selected object.',

      config_fields: [{
        name: 'object',
        optional: false,
        control_type: 'select',
        pick_list: 'standard_objects'
      }],

      input_fields: lambda do |object_definitions|
        [{ name: 'RECORDNO', label: 'Record number', optional: false }].
          concat(object_definitions['custom_field'])
      end,

      execute: lambda do |_connection, input|
        function = {
          '@controlid' => 'testControlId',
          'update' => {
            (object = input.delete('object')) => {
              'RECORDNO' => input.delete('RECORDNO'),
              'customfields' => [{
                'customfield' => input.map do |key, value|
                  {
                    'customfieldname' => key,
                    'customfieldvalue' => value
                  }
                end
              }]
            }
          }
        }
        response_data = call('get_api_response_data_element', function)

        call('parse_xml_to_hash',
             'xml' => response_data,
             'array_fields' => [object.downcase])&.dig(object.downcase, 0) || {}
      end,

      output_fields: lambda do |_object_definitions|
        [{ name: 'RECORDNO', label: 'Record number' }]
      end,

      sample_output: ->(_connection, _input) { { 'RECORDNO' => 1234 } }
    },

    get_so_n_po_custom_fields: {
      title: 'Get sales/purchase order custom fields',
      description: "Get <span class='provider'>custom fields</span> of " \
      "sales order/purchase order document in <span class='provider'>" \
      'Sage Intacct (Custom)</span>',

      input_fields: lambda do |_object_definitions|
        [
          {
            name: 'object',
            optional: false,
            control_type: 'select',
            pick_list: 'so_po_objects'
          },
          {
            name: 'document_type',
            label: 'Document type',
            optional: false,
            control_type: 'select',
            pick_list: 'document_types',
            pick_list_params: { object: 'object' },
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'document_type',
              label: 'Document type',
              hint: 'Provide the document type of SO/PO, e.g., Sales Quote, ' \
              'Sales Invoice, Sales Order, Purchase Requisition, ' \
              'Purchase Order, Vendor Invoice, etc.',
              toggle_hint: 'Use custom value',
              optional: false,
              control_type: 'text',
              type: 'string'
            }
          },
          { name: 'RECORDNO', label: 'Record number', optional: false },
          # TODO: replace this with meta-data API on SO and PO
          {
            name: 'custom_fields',
            hint: 'Provide comma-separated custom field names. ' \
            'Find this custom field name as "Integration Name" of the ' \
            'field, on the "Object Definition" page of the corresponding ' \
            'object. E.g., EXTERNAL_ID, SYNC_STATUS',
            optional: false,
            extends_schema: true
          }
        ]
      end,

      execute: lambda do |_connection, input|
        function = {
          '@controlid' => 'testControlId',
          'readByQuery' => {
            'object' => (object = input['object']),
            'docparid' => input['document_type'],
            'fields' => '*',
            'query' => "RECORDNO = '#{input['RECORDNO']}'",
            'returnFormat' => 'xml'
          }
        }
        response_data = call('get_api_response_data_element', function)
        call('parse_xml_to_hash',
             'xml' => response_data,
             'array_fields' => [object.downcase])&.
          dig(object.downcase, 0)
      end,

      output_fields: lambda do |object_definitions|
        [{ name: 'RECORDNO', label: 'Record number' }].
          concat(object_definitions['so_n_po_custom_field_out'])
      end,

      sample_output: ->(_connection, _input) { { 'RECORDNO' => 1234 } }
    },

    update_so_n_po_custom_fields: {
      title: 'Update sales/purchase order custom fields',
      description: "Update <span class='provider'>custom fields</span> " \
      "of sales order/purchase order document in <span class='provider'>" \
      'Sage Intacct (Custom)</span>',

      input_fields: lambda do |object_definitions|
        object_definitions['so_n_po_custom_field_update']
      end,

      execute: lambda do |_connection, input|
        # TODO: change this to legacy API payload rather
        function = {
          '@controlid' => 'testControlId',
          'update' => {
            (object = input.delete('object')) => {
              'RECORDNO' => input.delete('RECORDNO'),
              'customfields' => [{
                'customfield' =>
                input.except('custom_fields').map do |key, value|
                  {
                    'customfieldname' => key,
                    'customfieldvalue' => value
                  }
                end
              }]
            }
          }
        }
        response_data = call('get_api_response_data_element', function)

        call('parse_xml_to_hash',
             'xml' => response_data,
             'array_fields' => [object.downcase])&.dig(object.downcase, 0) || {}
      end,

      output_fields: lambda do |_object_definitions|
        [{ name: 'RECORDNO', label: 'Record number' }]
      end,

      sample_output: ->(_connection, _input) { { 'RECORDNO' => 1234 } }
    },

    # Customers
    create_customers_in_batch: {
      description: "Create <span class='provider'>customers</span> in a " \
      "batch in <span class='provider'>Sage Intacct (Custom)</span>",
      help: 'Custom fields are supported in this action. Provide a list of ' \
      'records to be created as the input. The maximum number of customers ' \
      'in a batch is 100.',

      execute: lambda do |connection, input, _input_schema, _output_schema|
        function = call('deep_compact', input).
                   dig('operation_element', 'function')
        if (batch_len = function&.length || 0) > 100
          error('The batch size limit for the action is 100. ' \
            "But the current batch has got #{batch_len} customers.")
        end
        payload = {
          'control' => input['control_element'] || {},
          'operation' => {
            '@transaction' => input.dig('operation_element', 'transaction'),
            'authentication' => {},
            'content' => { 'function' => function }.compact
          }.compact
        }

        call('get_api_response_element',
             'connection' => connection,
             'payload' => payload)
      end,

      input_fields: lambda do |object_definitions|
        object_definitions['customer_batch_create_input']
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['customer_batch_create_output']
      end,

      sample_output: lambda do |_connection, _input|
        {
          operation: {
            result: [{
              status: 'success',
              function: 'create',
              controlid: 'ID-007',
              data: {
                '@count' => '1',
                'customer' => {
                  'RECORDNO' => '7',
                  'CUSTOMERID' => 'CUST-007'
                }
              },
              errormessage: {
                error: [{
                  errorno: 'BL01001973',
                  description2: 'Currently, we can&#039;t create the ' \
                  'transaction',
                  correction: 'Check the transaction for errors or ' \
                  'inconsistencies, then try again.'
                }]
              }
            }]
          }
        }
      end
    },

    search_customers_query: {
      title: 'Search customers',
      description: "Search <span class='provider'>Customers</span> in " \
      "<span class='provider'>Sage Intacct (Custom)</span>",
      help: 'Search will return results that match all your search criteria. ' \
      'Returns a maximum of 2000 records.',

      execute: lambda do |_connection, input|
        field_function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'CUSTOMER' }
        }
        get_fields_response = call('get_api_response_data_element', field_function)
        fields =
          call('parse_xml_to_hash',
               'xml' => get_fields_response,
               'array_fields' => ['Field'])&.
          dig('Type', 'Fields', 'Field')&.pluck('Name')&.
          reject { |name| %w[ACTIVATIONDATE SUBSCRIPTIONENDDATE].include?(name) }
        select_fields =  { 'field' => input['fields']&.split(',') || fields }
        filter_condition = input['filter_condition'] || 'and'
        query =
          if input['filters'].present?
            if input['filters'].size > 1
              {
                filter_condition =>
                  input['filters']&.map do |filter|
                    { filter['operator'] => { 'field' => filter['field'],
                                              'value' => filter['value']&.split(',') } }
                  end&.each_with_object({}) do |hash, object|
                    hash.each { |key, value| (object[key] ||= []) << value }
                  end
              }
            elsif input['filters'].size == 1
              input['filters']&.map do |filter|
                { filter['operator'] => { 'field' => filter['field'],
                                          'value' => filter['value']&.split(',') } }
              end&.first
            end
          end
        orderby = if input['ordering'].present?
                    { 'order' => { 'field' => input['ordering']['sort_field'],
                                   input['ordering']['sort_order'] => '' } }
                  end
        function = {
          '@controlid' => 'testControlId',
          'query' => {
            'object' => 'CUSTOMER',
            'select' => select_fields,
            'filter' => query,
            'orderby' => orderby,
            'options' => input['options'],
            'pagesize' => input['pagesize'] || 100,
            'offset' => input['offset'] || 0
          }.compact
        }
        response_data = call('get_api_response_data_element', function)

        {
          customers: call('format_response',
                          call('parse_xml_to_hash',
                               'xml' => response_data,
                               'array_fields' => ['CUSTOMER'])&.
                          []('CUSTOMER')) || []
        }
      end,

      input_fields: ->(object_definitions) { object_definitions['customer_search'] },

      output_fields: lambda do |object_definitions|
        [{
          name: 'customers',
          type: 'array',
          of: 'object',
          properties: object_definitions['customer']
        }]
      end,

      sample_output: lambda do |_connection, _input|
        field_function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'CUSTOMER' }
        }
        get_fields_response = call('get_api_response_data_element', field_function)
        fields =
          call('parse_xml_to_hash',
               'xml' => get_fields_response,
               'array_fields' => ['Field'])&.
          dig('Type', 'Fields', 'Field')&.pluck('Name')&.
          reject { |name| %w[ACTIVATIONDATE SUBSCRIPTIONENDDATE].include?(name) }
        function = {
          '@controlid' => 'testControlId',
          'query' => {
            'object' => 'CUSTOMER',
            'select' => { 'field' => fields },
            'pagesize' => 1
          }.compact
        }
        response_data = call('get_api_response_data_element', function)

        {
          customers: call('format_response',
                          call('parse_xml_to_hash',
                               'xml' => response_data,
                               'array_fields' => ['CUSTOMER'])&.
                          []('CUSTOMER')) || []
        }
      end
    },

    # Contract
    create_contract: {
      description: "Create <span class='provider'>contract</span> in " \
      "<span class='provider'>Sage Intacct (Custom)</span>",
      help: 'Custom fields are supported in this action. <b>Make sure you ' \
      'have subscribed for Contract module in your Sage Intacct instance.</b>',

      input_fields: lambda do |object_definitions|
        object_definitions['contract_create']
      end,

      execute: lambda do |_connection, input|
        function = {
          '@controlid' => 'testControlId',
          'create' => { 'CONTRACT' => input }
        }
        response_data = call('get_api_response_data_element', function)

        call('parse_xml_to_hash',
             'xml' => response_data,
             'array_fields' => ['contract'])&.dig('contract', 0) || {}
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['contract_upsert'].only('RECORDNO', 'CONTRACTID')
      end,

      sample_output: lambda do |_connection, _input|
        { 'RECORDNO' => 1234, 'CONTRACTID' => 'CONTR-007' }
      end
    },

    search_contract: {
      title: 'Search contracts',
      description: "Search <span class='provider'>contracts</span>  in " \
      "<span class='provider'>Sage Intacct (Custom)</span>",
      help: 'Search will return results that match all your search criteria. ' \
      'Returns a maximum of 100 records. <b>Make sure you have  ' \
      'subscribed for Contract module in your Sage Intacct instance.</b>',
      deprecated: true,

      execute: lambda do |_connection, input|
        input = call('render_date_input', input)
        query = call('format_payload', input)&.
                map { |key, value| "#{key} = '#{value}'" }&.
                smart_join(' and ') || ''
        function = {
          '@controlid' => 'testControlId',
          'readByQuery' => {
            'object' => 'CONTRACT',
            'fields' => '*',
            'query' => query,
            'pagesize' => '100'
          }
        }
        response_data = call('get_api_response_data_element', function)

        {
          contracts: call('format_response',
                          call('parse_xml_to_hash',
                               'xml' => response_data,
                               'array_fields' => ['contract'])&.
                            []('contract')) || []
        }
      end,

      input_fields: lambda { |object_definitions|
        object_definitions['contract'].ignored('WHENCREATED', 'WHENMODIFIED')
      },

      output_fields: lambda do |object_definitions|
        [{
          name: 'contracts',
          type: 'array',
          of: 'object',
          properties: object_definitions['contract']
        }]
      end,

      sample_output: lambda do |_connection, _input|
        function = {
          '@controlid' => 'testControlId',
          'readByQuery' => {
            'object' => 'CONTRACT',
            'fields' => '*',
            'query' => '',
            'pagesize' => '1'
          }
        }
        response_data = call('get_api_response_data_element', function)

        {
          contracts: call('format_response',
                          call('parse_xml_to_hash',
                               'xml' => response_data,
                               'array_fields' => ['contract'])&.
                            []('contract')) || []
        }
      end
    },

    search_contract_query: {
      title: 'Search contracts',
      description: "Search <span class='provider'>Contracts</span>  in " \
      "<span class='provider'>Sage Intacct (Custom)</span>",
      help: 'Search will return results that match all your search criteria. ' \
      'Returns a maximum of 2000 records. <b>Make sure you have  ' \
      'subscribed for Contract module in your Sage Intacct instance.</b>',

      execute: lambda do |_connection, input|
        field_function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'CONTRACT' }
        }
        get_fields_response = call('get_api_response_data_element', field_function)
        fields =
          call('parse_xml_to_hash',
               'xml' => get_fields_response,
               'array_fields' => ['Field'])&.
          dig('Type', 'Fields', 'Field')&.
          select do |field|
            %w[CUSTOMERKEY BILLTOKEY SHIPTOKEY TERMKEY RENEWALMACROKEY RENEWEDCONTRACTKEY
               RENEWCONTRACT_SCHOPKEY RENEWEMAILALERT_SCHOPKEY NONRENEWCONTRACT_SCHOPKEY
               RENEWCUSTOMERALERT_SCHOPKEY PRCLSTKEY MEAPRCLSTKEY
               LOCATIONKEY DEPTKEY CUSTOM_PASSWORD].
              exclude?(field['Name'])
          end&.
          pluck('Name')
        select_fields =  { 'field' => input['fields']&.split(',') || fields }
        filter_condition = input['filter_condition'] || 'and'
        query =
          if input['filters'].present?
            if input['filters'].size > 1
              {
                filter_condition =>
                  input['filters']&.map do |filter|
                    { filter['operator'] => { 'field' => filter['field'],
                                              'value' => filter['value']&.split(',') } }
                  end&.each_with_object({}) do |hash, object|
                    hash.each { |key, value| (object[key] ||= []) << value }
                  end
              }
            elsif input['filters'].size == 1
              input['filters']&.map do |filter|
                { filter['operator'] => { 'field' => filter['field'],
                                          'value' => filter['value']&.split(',') } }
              end&.first
            end
          end
        orderby = if input['ordering'].present?
                    { 'order' => { 'field' => input['ordering']['sort_field'],
                                   input['ordering']['sort_order'] => '' } }
                  end
        function = {
          '@controlid' => 'testControlId',
          'query' => {
            'object' => 'CONTRACT',
            'select' => select_fields,
            'filter' => query,
            'orderby' => orderby,
            'options' => input['options'],
            'pagesize' => input['pagesize'] || 100,
            'offset' => input['offset'] || 0
          }.compact
        }
        response_data = call('get_api_response_data_element', function)

        {
          contracts: call('format_response',
                          call('parse_xml_to_hash',
                               'xml' => response_data,
                               'array_fields' => ['CONTRACT'])&.
                          []('CONTRACT')) || []
        }
      end,

      input_fields: ->(object_definitions) { object_definitions['contract_search'] },

      output_fields: lambda do |object_definitions|
        [{
          name: 'contracts',
          type: 'array',
          of: 'object',
          properties: object_definitions['contract']
        }]
      end,

      sample_output: lambda do |_connection, _input|
        field_function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'CONTRACT' }
        }
        get_fields_response = call('get_api_response_data_element', field_function)
        fields =
          call('parse_xml_to_hash',
               'xml' => get_fields_response,
               'array_fields' => ['Field'])&.
          dig('Type', 'Fields', 'Field')&.
          select do |field|
            %w[CUSTOMERKEY BILLTOKEY SHIPTOKEY TERMKEY RENEWALMACROKEY RENEWEDCONTRACTKEY
               RENEWCONTRACT_SCHOPKEY RENEWEMAILALERT_SCHOPKEY NONRENEWCONTRACT_SCHOPKEY
               RENEWCUSTOMERALERT_SCHOPKEY PRCLSTKEY MEAPRCLSTKEY LOCATIONKEY
               DEPTKEY CUSTOM_PASSWORD].
              exclude?(field['Name'])
          end&.
          pluck('Name')
        function = {
          '@controlid' => 'testControlId',
          'query' => {
            'object' => 'CONTRACT',
            'select' => { 'field' => fields },
            'pagesize' => 1
          }.compact
        }
        response_data = call('get_api_response_data_element', function)

        {
          contracts: call('format_response',
                          call('parse_xml_to_hash',
                               'xml' => response_data,
                               'array_fields' => ['CONTRACT'])&.
                          []('CONTRACT')) || []
        }
      end
    },

    get_contract_by_record_number: {
      description: "Get <span class='provider'>contract</span> by record " \
      "number in <span class='provider'>Sage Intacct (Custom)</span>",

      execute: lambda do |_connection, input|
        function = {
          '@controlid' => 'testControlId',
          'readByQuery' => {
            'object' => 'CONTRACT',
            'fields' => '*',
            'query' => "RECORDNO = '#{input['RECORDNO']}'",
            'pagesize' => '1'
          }
        }
        response_data = call('get_api_response_data_element', function)

        call('format_response',
             call('parse_xml_to_hash',
                  'xml' => response_data,
                  'array_fields' => ['contract'])&.
                dig('contract', 0)) || {}
      end,

      input_fields: lambda do |object_definitions|
        object_definitions['contract'].only('RECORDNO').required('RECORDNO')
      end,

      output_fields: ->(object_definitions) { object_definitions['contract'] },

      sample_output: lambda do |_connection, _input|
        function = {
          '@controlid' => 'testControlId',
          'readByQuery' => {
            'object' => 'CONTRACT',
            'fields' => '*',
            'query' => '',
            'pagesize' => '1'
          }
        }
        response_data = call('get_api_response_data_element', function)

        call('format_response',
             call('parse_xml_to_hash',
                  'xml' => response_data,
                  'array_fields' => ['contract'])&.
                          dig('contract', 0)) || {}
      end
    },

    update_contract: {
      description: "Update <span class='provider'>contract</span> in " \
      "<span class='provider'>Sage Intacct (Custom)</span>",
      help: 'Custom fields are supported in this action. <b>Make sure you ' \
      'have subscribed for Contract module in your Sage Intacct instance.</b>',

      execute: lambda do |_connection, input|
        unless (fields = input.keys)&.include?('RECORDNO') ||
               fields&.include?('CONTRACTID')
          error("Either 'Record number' or 'Contract ID' is required.")
        end
        function = {
          '@controlid' => 'testControlId',
          'update' => { 'CONTRACT' => input }
        }
        response_data = call('get_api_response_data_element', function)

        call('parse_xml_to_hash',
             'xml' => response_data,
             'array_fields' => ['contract'])&.dig('contract', 0) || {}
      end,

      input_fields: lambda do |object_definitions|
        object_definitions['contract_update']
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['contract_upsert'].only('RECORDNO', 'CONTRACTID')
      end,

      sample_output: lambda do |_connection, _input|
        { 'RECORDNO' => 1234, 'CONTRACTID' => 'CONTR-007' }
      end
    },

    search_contract_line: {
      title: 'Search contract lines',
      description: "Search <span class='provider'>contract lines</span>  in " \
      "<span class='provider'>Sage Intacct (Custom)</span>",
      help: 'Search will return results that match all your search criteria. ' \
      'Returns a maximum of 100 records.',
      deprecated: true,

      execute: lambda do |_connection, input|
        input = call('render_date_input', input)
        query = call('format_payload', input)&.
                map { |key, value| "#{key} = '#{value}'" }&.
                smart_join(' and ') || ''
        function = {
          '@controlid' => 'testControlId',
          'readByQuery' => {
            'object' => 'CONTRACTDETAIL',
            'fields' => '*',
            'query' => query,
            'pagesize' => '100'
          }
        }
        response_data = call('get_api_response_data_element', function)

        {
          contract_lines: call('format_response',
                               call('parse_xml_to_hash',
                                    'xml' => response_data,
                                    'array_fields' => ['contractdetail'])&.
                                 []('contractdetail')) || []
        }
      end,

      input_fields: lambda do |object_definitions|
        object_definitions['contract_line'].
          ignored('WHENCREATED', 'WHENMODIFIED')
      end,

      output_fields: lambda do |object_definitions|
        [{
          name: 'contract_lines',
          type: 'array',
          of: 'object',
          properties: object_definitions['contract_line']
        }]
      end,

      sample_output: lambda do |_connection, _input|
        function = {
          '@controlid' => 'testControlId',
          'readByQuery' => {
            'object' => 'CONTRACTDETAIL',
            'fields' => '*',
            'query' => '',
            'pagesize' => '1'
          }
        }
        response_data = call('get_api_response_data_element', function)

        {
          contract_lines: call('format_response',
                               call('parse_xml_to_hash',
                                    'xml' => response_data,
                                    'array_fields' => ['contractdetail'])&.
                                 []('contractdetail')) || []
        }
      end
    },

    search_contract_line_query: {
      title: 'Search contract lines',
      description: "Search <span class='provider'>Contract lines</span>  in " \
      "<span class='provider'>Sage Intacct (Custom)</span>",
      help: 'Search will return results that match all your search criteria. ' \
      'Returns a maximum of 2000 records.',

      execute: lambda do |_connection, input|
        field_function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'CONTRACTDETAIL' }
        }
        get_fields_response = call('get_api_response_data_element', field_function)
        fields =
          call('parse_xml_to_hash',
               'xml' => get_fields_response,
               'array_fields' => ['Field'])&.
          dig('Type', 'Fields', 'Field')&.
          select do |field|
            %w[SHORTITEMDESC REVENUEPOSTINGTYPE REVENUE2POSTINGTYPE REVPOSTINGCONVERSIONDATE
               REV2POSTINGCONVERSIONDATE CALCULATEDREVENUEPOSTINGTYPE
               CALCULATEDREVENUE2POSTINGTYPE].exclude?(field['Name'])
          end&.
          pluck('Name')
        select_fields =  { 'field' => input['fields']&.split(',') || fields }
        filter_condition = input['filter_condition'] || 'and'
        query =
          if input['filters'].present?
            if input['filters'].size > 1
              {
                filter_condition =>
                  input['filters']&.map do |filter|
                    { filter['operator'] => { 'field' => filter['field'],
                                              'value' => filter['value']&.split(',') } }
                  end&.each_with_object({}) do |hash, object|
                    hash.each { |key, value| (object[key] ||= []) << value }
                  end
              }
            elsif input['filters'].size == 1
              input['filters']&.map do |filter|
                { filter['operator'] => { 'field' => filter['field'],
                                          'value' => filter['value']&.split(',') } }
              end&.first
            end
          end
        orderby = if input['ordering'].present?
                    { 'order' => { 'field' => input['ordering']['sort_field'],
                                   input['ordering']['sort_order'] => '' } }
                  end
        function = {
          '@controlid' => 'testControlId',
          'query' => {
            'object' => 'CONTRACTDETAIL',
            'select' => select_fields,
            'filter' => query,
            'orderby' => orderby,
            'options' => input['options'],
            'pagesize' => input['pagesize'] || 100,
            'offset' => input['offset'] || 0
          }.compact
        }
        response_data = call('get_api_response_data_element', function)

        {
          contract_lines: call('format_response',
                               call('parse_xml_to_hash',
                                    'xml' => response_data,
                                    'array_fields' => ['CONTRACTDETAIL'])&.
                               []('CONTRACTDETAIL')) || []
        }
      end,

      input_fields: ->(object_definitions) { object_definitions['contract_line_search'] },

      output_fields: lambda do |object_definitions|
        [{
          name: 'contract_lines',
          type: 'array',
          of: 'object',
          properties: object_definitions['contract_line']
        }]
      end,

      sample_output: lambda do |_connection, _input|
        field_function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'CONTRACTDETAIL' }
        }
        get_fields_response = call('get_api_response_data_element', field_function)
        fields =
          call('parse_xml_to_hash',
               'xml' => get_fields_response,
               'array_fields' => ['Field'])&.
          dig('Type', 'Fields', 'Field')&.
          select do |field|
            %w[SHORTITEMDESC REVENUEPOSTINGTYPE REVENUE2POSTINGTYPE REVPOSTINGCONVERSIONDATE
               REV2POSTINGCONVERSIONDATE CALCULATEDREVENUEPOSTINGTYPE
               CALCULATEDREVENUE2POSTINGTYPE].exclude?(field['Name'])
          end&.
          pluck('Name')
        function = {
          '@controlid' => 'testControlId',
          'query' => {
            'object' => 'CONTRACTDETAIL',
            'select' => { 'field' => fields },
            'pagesize' => 1
          }.compact
        }
        response_data = call('get_api_response_data_element', function)

        {
          contract_lines: call('format_response',
                               call('parse_xml_to_hash',
                                    'xml' => response_data,
                                    'array_fields' => ['CONTRACTDETAIL'])&.
                               []('CONTRACTDETAIL')) || []
        }
      end
    },

    create_contract_line: {
      description: "Create <span class='provider'>contract line</span> in " \
      "<span class='provider'>Sage Intacct (Custom)</span>",
      help: 'Custom fields are supported in this action. <b>Make sure you ' \
      'have subscribed for Contract module in your Sage Intacct instance.</b>',

      execute: lambda do |_connection, input|
        function = {
          '@controlid' => 'testControlId',
          'create' => { 'CONTRACTDETAIL' => input }
        }
        response_data = call('get_api_response_data_element', function)

        call('parse_xml_to_hash',
             'xml' => response_data,
             'array_fields' => ['contractdetail'])&.
          dig('contractdetail', 0) || {}
      end,

      input_fields: lambda do |object_definitions|
        object_definitions['contract_line_create']
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['contract_line_upsert'].only('RECORDNO')
      end,

      sample_output: ->(_connection, _input) { { 'RECORDNO' => 1234 } }
    },

    hold_contract_line: {
      subtitle: 'Hold contract line in Sage Intacct (Custom)',
      description: "Hold <span class='provider'>contract line</span> in " \
      "<span class='provider'>Sage Intacct (Custom)</span>",
      help: 'When using this action, the contract line remains in progress, ' \
            'but the billing and revenue schedules and/or expense ' \
            'schedules can be put on hold.',

      execute: lambda do |_connection, input|
        function = {
          '@controlid' => 'testControlId',
          'hold' => { 'CONTRACTDETAIL' => input }
        }
        response_data = call('get_api_response_result_element', function)

        call('format_response', call('parse_xml_to_hash',
                                     'xml' => response_data,
                                     'array_fields' => []))
      end,

      input_fields: lambda do |object_definitions|
        object_definitions['contract_line_hold']
      end,

      output_fields: lambda do |_object_definitions|
        [
          { name: 'status' },
          { name: 'function' },
          { name: 'controlid', label: 'Control ID' }
        ]
      end,

      sample_output: lambda do |_connection, _input|
        { 'status' => 'success',
          'function' => 'hold',
          'controlid' => 'testControlId' }
      end
    },

    uncancel_contract_line: {
      subtitle: 'Uncancel contract line in Sage Intacct (Custom)',
      description: "Uncancel <span class='provider'>contract line</span> in " \
      "<span class='provider'>Sage Intacct (Custom)</span>",
      help: 'If you incorrectly or inadvertently canceled a contract line, ' \
            'you can use this action to uncancel the line.',

      execute: lambda do |_connection, input|
        function = {
          '@controlid' => 'testControlId',
          'uncancel' => { 'CONTRACTDETAIL' => input }
        }
        response_data = call('get_api_response_result_element', function)

        call('format_response', call('parse_xml_to_hash',
                                     'xml' => response_data,
                                     'array_fields' => []))
      end,

      input_fields: lambda do |object_definitions|
        object_definitions['contract_line_uncancel']
      end,

      output_fields: lambda do |_object_definitions|
        [
          { name: 'status' },
          { name: 'function' },
          { name: 'controlid', label: 'Control ID' }
        ]
      end,

      sample_output: lambda do |_connection, _input|
        { 'status' => 'success',
          'function' => 'hold',
          'controlid' => 'testControlId' }
      end
    },

    delete_contract_line: {
      subtitle: 'Delete contract line in Sage Intacct (Custom)',
      description: "Delete <span class='provider'>contract line</span> in " \
      "<span class='provider'>Sage Intacct (Custom)</span>",
      help: 'Deletes a contract line in Sage Intacct (Custom)',

      execute: lambda do |_connection, input|
        function = {
          '@controlid' => 'testControlId',
          'delete' => { 'object' => 'CONTRACTDETAIL', 'keys' => input['keys'] }
        }
        response_data = call('get_api_response_result_element', function)

        { status: call('parse_xml_to_hash',
                       'xml' => response_data,
                       'array_fields' => [])['status'] }
      end,

      input_fields: lambda do |_object_definitions|
        [{ name: 'keys', label: 'Record number', optional: false, hint: 'Multiple ' \
          'record numbers can applied by providing values separated by comma' }]
      end,

      output_fields: lambda do |_object_definitions|
        [
          { name: 'status' }
        ]
      end,

      sample_output: lambda do |_connection, _input|
        { 'status' => 'success' }
      end
    },

    renew_contract: {
      subtitle: 'Renew contract in Sage Intacct (Custom)',
      description: "Renew <span class='provider'>contract</span> in " \
      "<span class='provider'>Sage Intacct (Custom)</span>",
      help: 'Renew a contract in Sage Intacct (Custom)',

      execute: lambda do |_connection, input|
        function = {
          '@controlid' => 'testControlId',
          'renew' => { 'CONTRACT' => { 'CONTRACTID' => input['contract_id'] } }
        }
        response_data = call('get_api_response_result_element', function)

        { status: call('parse_xml_to_hash',
                       'xml' => response_data,
                       'array_fields' => [])['status'] }
      end,

      input_fields: lambda do |_object_definitions|
        [{ name: 'contract_id', optional: false,
           hint: 'ID of the contract to renew. ' \
           'The contract’s state must be In progress, ' \
           'and there must be at least one contract line.' }]
      end,

      output_fields: lambda do |_object_definitions|
        [
          { name: 'status' }
        ]
      end,

      sample_output: lambda do |_connection, _input|
        { 'status' => 'success' }
      end
    },

    # Contact-line
    create_contract_lines_in_batch: {
      description: "Create <span class='provider'>contract lines</span> in a " \
      "batch in <span class='provider'>Sage Intacct (Custom)</span>",
      help: 'Custom fields are supported in this action. Provide a list of ' \
      'records to be created as the input. The maximum number of ' \
      'contract lines in a batch is 100.',

      execute: lambda do |connection, input, _input_schema, _output_schema|
        function = call('deep_compact', input).
                   dig('operation_element', 'function')
        if (batch_len = function&.length || 0) > 100
          error('The batch size limit for the action is 100. ' \
          "But the current batch has got #{batch_len} contract lines.")
        end
        payload = {
          'control' => input['control_element'] || {},
          'operation' => {
            '@transaction' => input.dig('operation_element', 'transaction'),
            'authentication' => {},
            'content' => { 'function' => function }.compact
          }.compact
        }

        call('get_api_response_element',
             'connection' => connection,
             'payload' => payload)
      end,

      input_fields: lambda do |object_definitions, _connection, _config_fields|
        object_definitions['contract_line_batch_create_input']
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['contract_line_batch_create_output']
      end,

      sample_output: lambda do |_connection, _input|
        {
          operation: {
            result: [{
              status: 'success',
              function: 'create',
              controlid: 'ID-007',
              data: {
                '@count' => '1',
                'contractdetail' => { 'RECORDNO' => '7' }
              },
              errormessage: {
                error: [{
                  errorno: 'BL01001973',
                  description2: 'Currently, we can&#039;t create the ' \
                  'transaction',
                  correction: 'Check the transaction for errors or ' \
                  'inconsistencies, then try again.'
                }]
              }
            }]
          }
        }
      end
    },

    get_contract_line_by_record_number: {
      description: "Get <span class='provider'>contract line</span> by " \
      "record number in <span class='provider'>Sage Intacct (Custom)</span>",

      execute: lambda do |_connection, input|
        function = {
          '@controlid' => 'testControlId',
          'readByQuery' => {
            'object' => 'CONTRACTDETAIL',
            'fields' => '*',
            'query' => "RECORDNO = '#{input['RECORDNO']}'",
            'pagesize' => '1'
          }
        }
        response_data = call('get_api_response_data_element', function)

        call('format_response',
             call('parse_xml_to_hash',
                  'xml' => response_data,
                  'array_fields' => ['contractdetail'])&.
                dig('contractdetail', 0)) || {}
      end,

      input_fields: lambda do |object_definitions|
        object_definitions['contract_line'].
          only('RECORDNO').
          required('RECORDNO')
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['contract_line']
      end,

      sample_output: lambda do |_connection, _input|
        function = {
          '@controlid' => 'testControlId',
          'readByQuery' => {
            'object' => 'CONTRACTDETAIL',
            'fields' => '*',
            'query' => '',
            'pagesize' => '1'
          }
        }
        response_data = call('get_api_response_data_element', function)

        call('format_response',
             call('parse_xml_to_hash',
                  'xml' => response_data,
                  'array_fields' => ['contractdetail'])&.
               dig('contractdetail', 0)) || {}
      end
    },

    update_contract_line: {
      description: "Update <span class='provider'>contract line</span> in " \
      "<span class='provider'>Sage Intacct (Custom)</span>",
      help: 'Custom fields are supported in this action. <b>Make sure you ' \
      'have subscribed for Contract module in your Sage Intacct instance.</b>',

      execute: lambda do |_connection, input|
        function = {
          '@controlid' => 'testControlId',
          'update' => { 'CONTRACTDETAIL' => input }
        }
        response_data = call('get_api_response_data_element', function)

        call('parse_xml_to_hash',
             'xml' => response_data,
             'array_fields' => ['contractdetail'])&.
          dig('contractdetail', 0) || {}
      end,

      input_fields: lambda do |object_definitions|
        object_definitions['contract_line_update']
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['contract_line_upsert'].only('RECORDNO')
      end,

      sample_output: ->(_connection, _input) { { 'RECORDNO' => 1234 } }
    },

    search_contract_expense_line: {
      title: 'Search contract expense lines',
      description: "Search <span class='provider'>contract expense</span> " \
      "lines in <span class='provider'>Sage Intacct (Custom)</span>",
      help: 'Search will return results that match all your search criteria. ' \
      'Returns a maximum of 100 records. <b>Make sure you have  ' \
      'subscribed for Contract module in your Sage Intacct instance.</b>',
      deprecated: true,

      execute: lambda do |_connection, input|
        input = call('render_date_input', input)
        query = call('format_payload', input)&.
                map { |key, value| "#{key} = '#{value}'" }&.
                smart_join(' and ') || ''
        function = {
          '@controlid' => 'testControlId',
          'readByQuery' => {
            'object' => 'CONTRACTEXPENSE',
            'fields' => '*',
            'query' => query,
            'pagesize' => '100'
          }
        }
        response_data = call('get_api_response_data_element', function)

        {
          contract_expenses: call('format_response',
                                  call('parse_xml_to_hash',
                                       'xml' => response_data,
                                       'array_fields' => ['contractexpense'])&.
                                    []('contractexpense')) || []
        }
      end,

      input_fields: lambda do |object_definitions|
        object_definitions['contract_expense'].
          ignored('WHENCREATED', 'WHENMODIFIED')
      end,

      output_fields: lambda do |object_definitions|
        [{
          name: 'contract_expenses',
          type: 'array',
          of: 'object',
          properties: object_definitions['contract_expense']
        }]
      end,

      sample_output: lambda do |_connection, _input|
        function = {
          '@controlid' => 'testControlId',
          'readByQuery' => {
            'object' => 'CONTRACTEXPENSE',
            'fields' => '*',
            'query' => '',
            'pagesize' => '1'
          }
        }
        response_data = call('get_api_response_data_element', function)

        {
          contract_expenses: call('format_response',
                                  call('parse_xml_to_hash',
                                       'xml' => response_data,
                                       'array_fields' => ['contractexpense'])&.
                                    []('contractexpense')) || []
        }
      end
    },

    search_contract_expense_line_query: {
      title: 'Search contract expense lines',
      description: "Search <span class='provider'>Contract expense</span> " \
      "lines in <span class='provider'>Sage Intacct (Custom)</span>",
      help: 'Search will return results that match all your search criteria. ' \
      'Returns a maximum of 2000 records. <b>Make sure you have  ' \
      'subscribed for Contract module in your Sage Intacct instance.</b>',

      execute: lambda do |_connection, input|
        field_function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'CONTRACTEXPENSE' }
        }
        get_fields_response = call('get_api_response_data_element', field_function)
        fields =
          call('parse_xml_to_hash',
               'xml' => get_fields_response,
               'array_fields' => ['Field'])&.
          dig('Type', 'Fields', 'Field')&.
          select { |field| %w[CALCULATEDEXPENSEPOSTINGTYPE LINENO].exclude?(field['Name']) }&.
          pluck('Name')
        select_fields =  { 'field' => input['fields']&.split(',') || fields }
        filter_condition = input['filter_condition'] || 'and'
        query =
          if input['filters'].present?
            if input['filters'].size > 1
              {
                filter_condition =>
                  input['filters']&.map do |filter|
                    { filter['operator'] => { 'field' => filter['field'],
                                              'value' => filter['value']&.split(',') } }
                  end&.each_with_object({}) do |hash, object|
                    hash.each { |key, value| (object[key] ||= []) << value }
                  end
              }
            elsif input['filters'].size == 1
              input['filters']&.map do |filter|
                { filter['operator'] => { 'field' => filter['field'],
                                          'value' => filter['value']&.split(',') } }
              end&.first
            end
          end
        orderby = if input['ordering'].present?
                    { 'order' => { 'field' => input['ordering']['sort_field'],
                                   input['ordering']['sort_order'] => '' } }
                  end
        function = {
          '@controlid' => 'testControlId',
          'query' => {
            'object' => 'CONTRACTEXPENSE',
            'select' => select_fields,
            'filter' => query,
            'orderby' => orderby,
            'options' => input['options'],
            'pagesize' => input['pagesize'] || 100,
            'offset' => input['offset'] || 0
          }.compact
        }
        response_data = call('get_api_response_data_element', function)

        {
          contract_expenses: call('format_response',
                                  call('parse_xml_to_hash',
                                       'xml' => response_data,
                                       'array_fields' => ['CONTRACTEXPENSE'])&.
                                  []('CONTRACTEXPENSE')) || []
        }
      end,

      input_fields: ->(object_definitions) { object_definitions['contract_expense_search'] },

      output_fields: lambda do |object_definitions|
        [{
          name: 'contract_expenses',
          type: 'array',
          of: 'object',
          properties: object_definitions['contract_expense']
        }]
      end,

      sample_output: lambda do |_connection, _input|
        field_function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'CONTRACTEXPENSE' }
        }
        get_fields_response = call('get_api_response_data_element', field_function)
        fields =
          call('parse_xml_to_hash',
               'xml' => get_fields_response,
               'array_fields' => ['Field'])&.
          dig('Type', 'Fields', 'Field')&.
          select { |field| %w[CALCULATEDEXPENSEPOSTINGTYPE LINENO].exclude?(field['Name']) }&.
          pluck('Name')
        function = {
          '@controlid' => 'testControlId',
          'query' => {
            'object' => 'CONTRACTEXPENSE',
            'select' => { 'field' => fields },
            'pagesize' => 1
          }.compact
        }
        response_data = call('get_api_response_data_element', function)

        {
          contract_expenses: call('format_response',
                                  call('parse_xml_to_hash',
                                       'xml' => response_data,
                                       'array_fields' => ['CONTRACTEXPENSE'])&.
                                  []('CONTRACTEXPENSE')) || []
        }
      end
    },

    get_contract_expense_line_by_record_number: {
      description: "Get <span class='provider'>contract expense line</span> " \
      "by record number in <span class='provider'>Sage Intacct (Custom)</span>",

      execute: lambda do |_connection, input|
        function = {
          '@controlid' => 'testControlId',
          'readByQuery' => {
            'object' => 'CONTRACTEXPENSE',
            'fields' => '*',
            'query' => "RECORDNO = '#{input['RECORDNO']}'",
            'pagesize' => '1'
          }
        }
        response_data = call('get_api_response_data_element', function)

        call('format_response',
             call('parse_xml_to_hash',
                  'xml' => response_data,
                  'array_fields' => ['contractexpense'])&.
                dig('contractexpense', 0)) || {}
      end,

      input_fields: lambda do |object_definitions|
        object_definitions['contract_expense'].
          only('RECORDNO').
          required('RECORDNO')
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['contract_expense']
      end,

      sample_output: lambda do |_connection, _input|
        function = {
          '@controlid' => 'testControlId',
          'readByQuery' => {
            'object' => 'CONTRACTEXPENSE',
            'fields' => '*',
            'query' => '',
            'pagesize' => '1'
          }
        }
        response_data = call('get_api_response_data_element', function)

        call('format_response',
             call('parse_xml_to_hash',
                  'xml' => response_data,
                  'array_fields' => ['contractexpense'])&.
               dig('contractexpense', 0)) || {}
      end
    },

    # Attachment
    create_attachments: {
      description: "Create <span class='provider'>attachments</span> in " \
      "<span class='provider'>Sage Intacct (Custom)</span>",

      execute: lambda do |_connection, input, input_schema, _output_schema|
        input = call('format_input_to_match_schema',
                     'schema' => input_schema,
                     'input' => input)
        function = {
          '@controlid' => 'testControlId',
          'create_supdoc' => input['attachment']
        }
        response_result = call('get_api_response_result_element', function)

        call('parse_xml_to_hash',
             'xml' => response_result,
             'array_fields' => []) || {}
      end,

      input_fields: lambda do |object_definitions|
        object_definitions['supdoc_create']
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['legacy_create_or_update_response']
      end,

      sample_output: lambda do |_connection, _input|
        {
          status: 'success',
          function: 'create_supdoc',
          controlid: 'testControlId',
          key: 1234
        }
      end
    },

    get_attachment: {
      title: 'Get attachment by ID',
      description: "Get <span class='provider'>attachment</span> by ID in " \
      "<span class='provider'>Sage Intacct (Custom)</span>",

      execute: lambda do |_connection, input|
        function = {
          '@controlid' => 'testControlId',
          'get' => { '@object' => 'supdoc', '@key' => input['key'] }
        }
        response_data = call('get_api_response_data_element', function)

        call('parse_xml_to_hash',
             'xml' => response_data,
             'array_fields' => %w[supdoc attachment])&.dig('supdoc', 0) || {}
      end,

      input_fields: lambda do |_object_definitions|
        [{ name: 'key', label: 'Supporting document ID', optional: false }]
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['supdoc_get'].
          ignored('supdocfoldername', 'supdocdescription')
      end,

      sample_output: lambda do |_connection, _input|
        function = {
          '@controlid' => 'testControlId',
          'get_list' => { '@object' => 'supdoc', '@maxitems' => '1' }
        }
        response_data = call('get_api_response_data_element', function)

        call('parse_xml_to_hash',
             'xml' => response_data,
             'array_fields' => %w[supdoc attachment])&.dig('supdoc', 0) || {}
      end
    },

    update_attachment: {
      description: "Update <span class='provider'>attachment</span> in " \
      "<span class='provider'>Sage Intacct (Custom)</span>",

      execute: lambda do |_connection, input, input_schema, _output_schema|
        function = call('format_input_to_match_schema',
                        'schema' => input_schema,
                        'input' => input).merge('@controlid' => 'testControlId')
        response_result = call('get_api_response_result_element', function)

        call('parse_xml_to_hash',
             'xml' => response_result,
             'array_fields' => []) || {}
      end,

      input_fields: lambda do |object_definitions|
        {
          name: 'update_supdoc',
          label: 'Update attachment',
          optional: false,
          type: 'object',
          properties: object_definitions['supdoc_get'].
            ignored('creationdate', 'createdby', 'lastmodified',
                    'lastmodifiedby', 'folder', 'description').
            required('supdocid')
        }
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['legacy_create_or_update_response']
      end,

      sample_output: lambda do |_connection, _input|
        {
          status: 'success',
          function: 'update_supdoc',
          controlid: 'testControlId',
          key: 1234
        }
      end
    },

    # Attachment folder
    create_attachment_folder: {
      description: "Create <span class='provider'>attachment folder</span> " \
      "in <span class='provider'>Sage Intacct (Custom)</span>",

      execute: lambda do |_connection, input, input_schema, _output_schema|
        function = call('format_input_to_match_schema',
                        'schema' => input_schema,
                        'input' => input).merge('@controlid' => 'testControlId')
        response_result = call('get_api_response_result_element', function)

        call('parse_xml_to_hash',
             'xml' => response_result,
             'array_fields' => []) || {}
      end,

      input_fields: lambda do |object_definitions|
        {
          name: 'create_supdocfolder',
          label: 'Create attachment folder',
          optional: false,
          type: 'object',
          properties: object_definitions['supdocfolder'].
            ignored('creationdate', 'createdby', 'lastmodified',
                    'lastmodifiedby', 'name', 'description', 'parentfolder').
            required('supdocfoldername')
        }
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['legacy_create_or_update_response']
      end,

      sample_output: lambda do |_connection, _input|
        {
          status: 'success',
          function: 'create_supdocfolder',
          controlid: 'testControlId',
          key: 1234
        }
      end
    },

    get_attachment_folder: {
      title: 'Get attachment folder by folder name',
      description: "Get <span class='provider'>attachment folder</span> by " \
      "folder name in <span class='provider'>Sage Intacct (Custom)</span>",

      execute: lambda do |_connection, input|
        function = {
          '@controlid' => 'testControlId',
          'get' => { '@object' => 'supdocfolder', '@key' => input['key'] }
        }
        response_data = call('get_api_response_data_element', function)

        call('parse_xml_to_hash',
             'xml' => response_data,
             'array_fields' => ['supdocfolder'])&.dig('supdocfolder', 0) || {}
      end,

      input_fields: lambda do |_object_definitions|
        [{ name: 'key', label: 'Folder name', optional: false }]
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['supdocfolder'].
          ignored('supdocfoldername', 'supdocfolderdescription',
                  'supdocparentfoldername')
      end,

      sample_output: lambda do |_connection, _input|
        function = {
          '@controlid' => 'testControlId',
          'get_list' => { '@object' => 'supdocfolder', '@maxitems' => '1' }
        }
        response_data = call('get_api_response_data_element', function)

        call('parse_xml_to_hash',
             'xml' => response_data,
             'array_fields' => ['supdocfolder'])&.dig('supdocfolder', 0) || {}
      end
    },

    update_attachment_folder: {
      description: "Update <span class='provider'>attachment folder</span> " \
      "in <span class='provider'>Sage Intacct (Custom)</span>",

      execute: lambda do |_connection, input, input_schema, _output_schema|
        function = call('format_input_to_match_schema',
                        'schema' => input_schema,
                        'input' => input).merge('@controlid' => 'testControlId')
        response_result = call('get_api_response_result_element', function)

        call('parse_xml_to_hash',
             'xml' => response_result,
             'array_fields' => []) || {}
      end,

      input_fields: lambda do |object_definitions|
        {
          name: 'update_supdocfolder',
          label: 'Update attachment folder',
          optional: false,
          type: 'object',
          properties: object_definitions['supdocfolder'].
            ignored('creationdate', 'createdby', 'lastmodified',
                    'lastmodifiedby', 'name', 'description', 'parentfolder').
            required('supdocfoldername')
        }
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['legacy_create_or_update_response']
      end,

      sample_output: lambda do |_connection, _input|
        {
          status: 'success',
          function: 'update_supdocfolder',
          controlid: 'testControlId',
          key: 1234
        }
      end
    },

    # Employee
    create_employee: {
      description: "Create <span class='provider'>employee</span> in " \
      "<span class='provider'>Sage Intacct (Custom)</span>",
      help: 'Custom fields are supported in this action.',

      execute: lambda do |_connection, input|
        function = {
          '@controlid' => 'testControlId',
          'create' => { 'EMPLOYEE' => input }
        }
        response_data = call('get_api_response_data_element', function)

        call('parse_xml_to_hash',
             'xml' => response_data,
             'array_fields' => ['employee'])&.dig('employee', 0) || {}
      end,

      input_fields: lambda do |object_definitions|
        object_definitions['employee_create']
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['employee_get'].only('RECORDNO', 'EMPLOYEEID')
      end,

      sample_output: lambda do |_connection, _input|
        { 'RECORDNO' => 1234, 'EMPLOYEEID' => 'EMP-007' }
      end
    },

    get_employee: {
      title: 'Get employee by record number',
      description: "Get <span class='provider'>employee</span> in " \
      "<span class='provider'>Sage Intacct (Custom)</span>",

      execute: lambda do |_connection, input|
        function = {
          '@controlid' => 'testControlId',
          'readByQuery' => {
            'object' => 'EMPLOYEE',
            'fields' => '*',
            'query' => "RECORDNO = '#{input['RECORDNO']}'",
            'pagesize' => '1'
          }
        }
        response_data = call('get_api_response_data_element', function)

        call('parse_xml_to_hash',
             'xml' => response_data,
             'array_fields' => ['employee'])&.dig('employee', 0) || {}
      end,

      input_fields: lambda do |object_definitions|
        object_definitions['employee_get'].only('RECORDNO').required('RECORDNO')
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['employee_get']
      end,

      sample_output: lambda do |_connection, _input|
        function = {
          '@controlid' => 'testControlId',
          'readByQuery' => {
            'object' => 'EMPLOYEE',
            'query' => '',
            'fields' => '*',
            'pagesize' => '1'
          }
        }
        response_data = call('get_api_response_data_element', function)

        call('parse_xml_to_hash',
             'xml' => response_data,
             'array_fields' => ['employee'])&.dig('employee', 0) || {}
      end
    },

    search_employees: {
      description: "Search <span class='provider'>employees</span> in " \
      "<span class='provider'>Sage Intacct (Custom)</span>",
      help: 'Search will return results that match all your search criteria. ' \
      'Returns a maximum of 100 records.',
      deprecated: true,

      execute: lambda do |_connection, input|
        query = input&.map { |key, value| "#{key} = '#{value}'" }&.
                     smart_join(' AND ') || ''
        function = {
          '@controlid' => 'testControlId',
          'readByQuery' => {
            'object' => 'EMPLOYEE',
            'fields' => '*',
            'query' => query,
            'pagesize' => '100'
          }
        }
        response_data = call('get_api_response_data_element', function)

        {
          employees: call('format_response',
                          call('parse_xml_to_hash',
                               'xml' => response_data,
                               'array_fields' => ['employee'])&.
                            []('employee')) || []
        }
      end,

      input_fields: lambda do |object_definitions|
        object_definitions['employee_get'].
          only('RECORDNO', 'EMPLOYEEID', 'TITLE', 'DEPARTMENTID',
               'LOCATIONID', 'CLASSID')
      end,

      output_fields: lambda do |object_definitions|
        [{
          name: 'employees',
          type: 'array',
          of: 'object',
          properties: object_definitions['employee']
        }]
      end,

      sample_output: lambda do |_connection, _input|
        function = {
          '@controlid' => 'testControlId',
          'readByQuery' => {
            'object' => 'EMPLOYEE',
            'query' => '',
            'fields' => '*',
            'pagesize' => '1'
          }
        }
        response_data = call('get_api_response_data_element', function)

        {
          employees: call('parse_xml_to_hash',
                          'xml' => response_data,
                          'array_fields' => ['employee'])['employee'] || []
        }
      end
    },

    search_employees_query: {
      title: 'Search employees',
      description: "Search <span class='provider'>Employees</span> in " \
      "<span class='provider'>Sage Intacct (Custom)</span>",
      help: 'Search will return results that match all your search criteria. ' \
      'Returns a maximum of 2000 records.',

      execute: lambda do |_connection, input|
        field_function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'EMPLOYEE' }
        }
        get_fields_response = call('get_api_response_data_element', field_function)
        fields =
          call('parse_xml_to_hash',
               'xml' => get_fields_response,
               'array_fields' => ['Field'])&.
          dig('Type', 'Fields', 'Field')&.pluck('Name')
        select_fields =  { 'field' => input['fields']&.split(',') || fields }
        filter_condition = input['filter_condition'] || 'and'
        query =
          if input['filters'].present?
            if input['filters'].size > 1
              {
                filter_condition =>
                  input['filters']&.map do |filter|
                    { filter['operator'] => { 'field' => filter['field'],
                                              'value' => filter['value']&.split(',') } }
                  end&.each_with_object({}) do |hash, object|
                    hash.each { |key, value| (object[key] ||= []) << value }
                  end
              }
            elsif input['filters'].size == 1
              input['filters']&.map do |filter|
                { filter['operator'] => { 'field' => filter['field'],
                                          'value' => filter['value']&.split(',') } }
              end&.first
            end
          end
        orderby = if input['ordering'].present?
                    { 'order' => { 'field' => input['ordering']['sort_field'],
                                   input['ordering']['sort_order'] => '' } }
                  end
        function = {
          '@controlid' => 'testControlId',
          'query' => {
            'object' => 'EMPLOYEE',
            'select' => select_fields,
            'filter' => query,
            'orderby' => orderby,
            'options' => input['options'],
            'pagesize' => input['pagesize'] || 100,
            'offset' => input['offset'] || 0
          }.compact
        }
        response_data = call('get_api_response_data_element', function)

        {
          employees: call('format_response',
                          call('parse_xml_to_hash',
                               'xml' => response_data,
                               'array_fields' => ['EMPLOYEE'])&.
                          []('EMPLOYEE')) || []
        }
      end,

      input_fields: ->(object_definitions) { object_definitions['employee_search'] },

      output_fields: lambda do |object_definitions|
        [{
          name: 'employees',
          type: 'array',
          of: 'object',
          properties: object_definitions['employee']
        }]
      end,

      sample_output: lambda do |_connection, _input|
        field_function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'EMPLOYEE' }
        }
        get_fields_response = call('get_api_response_data_element', field_function)
        fields =
          call('parse_xml_to_hash',
               'xml' => get_fields_response,
               'array_fields' => ['Field'])&.
          dig('Type', 'Fields', 'Field')&.pluck('Name')
        function = {
          '@controlid' => 'testControlId',
          'query' => {
            'object' => 'EMPLOYEE',
            'select' => { 'field' => fields },
            'pagesize' => 1
          }.compact
        }
        response_data = call('get_api_response_data_element', function)

        {
          employees: call('format_response',
                          call('parse_xml_to_hash',
                               'xml' => response_data,
                               'array_fields' => ['EMPLOYEE'])&.
                          []('EMPLOYEE')) || []
        }
      end
    },

    update_employee: {
      description: "Update <span class='provider'>employee</span> in " \
      "<span class='provider'>Sage Intacct (Custom)</span>",
      help: 'Custom fields are supported in this action.',

      execute: lambda do |_connection, input|
        unless (fields = input.keys)&.include?('RECORDNO') ||
               fields&.include?('EMPLOYEEID')
          error("Either 'Record number' or 'Employee ID' is required.")
        end
        function = {
          '@controlid' => 'testControlId',
          'update' => { 'EMPLOYEE' => input }
        }
        response_data = call('get_api_response_data_element', function)

        call('parse_xml_to_hash',
             'xml' => response_data,
             'array_fields' => ['employee'])&.dig('employee', 0) || {}
      end,

      input_fields: lambda do |object_definitions|
        object_definitions['employee_update']
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['employee_get'].only('RECORDNO', 'EMPLOYEEID')
      end,

      sample_output: lambda do |_connection, _input|
        { 'RECORDNO' => 1234, 'EMPLOYEEID' => 'EMP-007' }
      end
    },

    # GL Entry
    create_gl_entry: {
      title: 'Create journal entry',
      description: "Create <span class='provider'>journal entry</span> in " \
      "<span class='provider'>Sage Intacct (Custom)</span>",
      help: 'Custom fields are supported in this action.',

      execute: lambda do |_connection, input|
        function = {
          '@controlid' => 'testControlId',
          'create' => { 'GLBATCH' => input }
        }
        response_data = call('get_api_response_data_element', function)

        call('parse_xml_to_hash',
             'xml' => response_data,
             'array_fields' => ['glbatch'])&.dig('glbatch', 0) || {}
      end,

      input_fields: lambda do |object_definitions|
        object_definitions['gl_batch'].
          ignored('RECORDNO').
          required('JOURNAL', 'BATCH_DATE', 'BATCH_TITLE', 'ENTRIES')
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['update_response']
      end,

      sample_output: ->(_connection, _input) { { 'RECORDNO' => 1234 } }
    },

    create_gl_entry_in_batch: {
      title: 'Create journal entries in batch',
      description: "Create <span class='provider'>journal entry</span> in " \
      "a batch in <span class='provider'>Sage Intacct (Custom)</span>",
      help: 'Custom fields are supported in this action. Provide a list of ' \
      'records to be created as the input. The maximum number of AR ' \
      'adjustments in a batch is 100.',

      execute: lambda do |connection, input, input_schema, _output_schema|
        input = call('format_input_to_match_schema',
                     'schema' => input_schema,
                     'input' => call('deep_compact', input))
        function = input.dig('operation_element', 'function')
        if (batch_len = function&.length || 0) > 100
          error('The batch size limit for the action is 100. ' \
            "But the current batch has got #{batch_len} Journal Entries.")
        end
        payload = {
          'control' => input['control_element'] || {},
          'operation' => {
            '@transaction' => input.dig('operation_element', 'transaction'),
            'authentication' => {},
            'content' => { 'function' => function }.compact
          }.compact
        }

        call('get_api_response_element',
             'connection' => connection,
             'payload' => payload)
      end,

      input_fields: lambda do |object_definitions|
        object_definitions['gl_batch_create_input']
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['gl_batch_create_output']
      end,

      sample_output: lambda do |_connection, _input|
        {
          operation: {
            result: [{
              status: 'success',
              function: 'create_gl_entry',
              controlid: 'ID-007',
              key: '1234',
              errormessage: {
                error: [{
                  errorno: 'BL01001973',
                  description2: 'Currently, we can&#039;t create the ' \
                  'transaction',
                  correction: 'Check the transaction for errors or ' \
                  'inconsistencies, then try again.'
                }]
              }
            }]
          }
        }
      end
    },

    update_gl_entry: {
      title: 'Update journal entry',
      description: "Update <span class='provider'>journal entry</span> in " \
      "<span class='provider'>Sage Intacct (Custom)</span>",
      help: 'Custom fields are supported in this action.',

      execute: lambda do |_connection, input|
        function = {
          '@controlid' => 'testControlId',
          'update' => { 'GLBATCH' => input }
        }
        response_data = call('get_api_response_data_element', function)

        call('parse_xml_to_hash',
             'xml' => response_data,
             'array_fields' => ['glbatch'])&.dig('glbatch', 0) || {}
      end,

      input_fields: lambda do |object_definitions|
        object_definitions['gl_batch'].
          ignored('JOURNAL', 'REVERSEDATE').
          required('RECORDNO', 'BATCH_DATE', 'BATCH_TITLE', 'ENTRIES')
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['update_response']
      end,

      sample_output: ->(_connection, _input) { { 'RECORDNO' => 1234 } }
    },

    # Invoice
    search_invoices_query: {
      title: 'Search invoices',
      description: "Search <span class='provider'>Invoices</span> in " \
      "<span class='provider'>Sage Intacct (Custom)</span>",
      help: 'Search will return results that match all your search criteria. ' \
      'Returns a maximum of 2000 records.',

      execute: lambda do |_connection, input|
        field_function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'ARINVOICE' }
        }
        get_fields_response = call('get_api_response_data_element', field_function)
        fields =
          call('parse_xml_to_hash',
               'xml' => get_fields_response,
               'array_fields' => ['Field'])&.
          dig('Type', 'Fields', 'Field')&.pluck('Name')&.
          reject { |name| %w[ENTITY CUSTENTITY RETAINAGEINVTYPE].include?(name) }
        select_fields =  { 'field' => input['fields']&.split(',') || fields }
        filter_condition = input['filter_condition'] || 'and'
        query =
          if input['filters'].present?
            if input['filters'].size > 1
              {
                filter_condition =>
                  input['filters']&.map do |filter|
                    { filter['operator'] => { 'field' => filter['field'],
                                              'value' => filter['value']&.split(',') } }
                  end&.each_with_object({}) do |hash, object|
                    hash.each { |key, value| (object[key] ||= []) << value }
                  end
              }
            elsif input['filters'].size == 1
              input['filters']&.map do |filter|
                { filter['operator'] => { 'field' => filter['field'],
                                          'value' => filter['value']&.split(',') } }
              end&.first
            end
          end
        orderby = if input['ordering'].present?
                    { 'order' => { 'field' => input['ordering']['sort_field'],
                                   input['ordering']['sort_order'] => '' } }
                  end
        function = {
          '@controlid' => 'testControlId',
          'query' => {
            'object' => 'ARINVOICE',
            'select' => select_fields,
            'filter' => query,
            'orderby' => orderby,
            'options' => input['options'],
            'pagesize' => input['pagesize'] || 100,
            'offset' => input['offset'] || 0
          }.compact
        }
        response_data = call('get_api_response_data_element', function)

        {
          invoices: call('format_response',
                         call('parse_xml_to_hash',
                              'xml' => response_data,
                              'array_fields' => ['ARINVOICE'])&.
                         []('ARINVOICE')) || []
        }
      end,

      input_fields: ->(object_definitions) { object_definitions['invoice_search'] },

      output_fields: lambda do |object_definitions|
        [{
          name: 'invoices',
          type: 'array',
          of: 'object',
          properties: object_definitions['invoice']
        }]
      end,

      sample_output: lambda do |_connection, _input|
        field_function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'ARINVOICE' }
        }
        get_fields_response = call('get_api_response_data_element', field_function)
        fields =
          call('parse_xml_to_hash',
               'xml' => get_fields_response,
               'array_fields' => ['Field'])&.
          dig('Type', 'Fields', 'Field')&.pluck('Name')&.
          reject { |name| %w[ENTITY CUSTENTITY RETAINAGEINVTYPE].include?(name) }
        function = {
          '@controlid' => 'testControlId',
          'query' => {
            'object' => 'ARINVOICE',
            'select' => { 'field' => fields },
            'pagesize' => 1
          }.compact
        }
        response_data = call('get_api_response_data_element', function)

        {
          invoices: call('format_response',
                         call('parse_xml_to_hash',
                              'xml' => response_data,
                              'array_fields' => ['ARINVOICE'])&.
                         []('ARINVOICE')) || []
        }
      end
    },

    create_invoice: {
      title: 'Create invoice',
      description: "Create <span class='provider'>Invoice</span> in " \
      "<span class='provider'>Sage Intacct (Custom)</span>",
      help: {
        body: 'Sage Intacct API requires fields to be sent in a certain order. ' \
        'Fields in this action are defined in the order that Sage Intacct expects them to be. ' \
        'Required fields and fields where one must be defined are shown by default. ' \
        'Kindly select all the optional fields that you need before filling ' \
        'up the data from top to bottom.',
        learn_more_url: 'https://developer.intacct.com/api/accounts-receivable/' \
        'invoices/#create-invoice-legacy',
        learn_more_text: 'Learn more'
      },

      execute: lambda do |_connection, input, input_schema, _output_schema|
        function = call('format_input_to_match_schema',
                        'schema' => input_schema,
                        'input' => input).merge('@controlid' => 'testControlId')
        response_data = call('get_api_response_result_element', function)

        call('parse_xml_to_hash',
             'xml' => response_data,
             'array_fields' => []) || {}
      end,

      input_fields: lambda do |object_definitions|
        object_definitions['invoice_create_single']
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['legacy_create_or_update_response']
      end,

      sample_output: lambda do |_connection, _input|
        {
          status: 'success',
          function: 'create_aradjustment',
          controlid: 'testControlId',
          key: 1234
        }
      end
    },

    get_invoice_items: {
      title: 'Get invoice items',
      description: "Get <span class='provider'>Invoice items" \
      "</span>  in <span class='provider'>Sage Intacct (Custom)</span>",

      execute: lambda do |_connection, input|
        function = {
          '@controlid' => 'testControlId',
          'readByQuery' => {
            'object' => 'ARINVOICEITEM',
            'fields' => '*',
            'query' => "RECORDKEY IN (#{input['RECORDNO']})",
            'pagesize' => '100'
          }
        }
        response_data = call('get_api_response_data_element', function)

        {
          invoice_items: call('format_response',
                              call('parse_xml_to_hash',
                                   'xml' => response_data,
                                   'array_fields' => ['arinvoiceitem'])&.
                                []('arinvoiceitem')) || []
        }
      end,

      input_fields: lambda do |_object_definitions|
        [{ name: 'RECORDNO', label: 'Invoice record number', optional: false }]
      end,

      output_fields: lambda do |object_definitions|
        [{
          name: 'invoice_items',
          type: 'array',
          of: 'object',
          properties: object_definitions['invoice_item']
        }]
      end,

      sample_output: lambda do |_connection, _input|
        function = {
          '@controlid' => 'testControlId',
          'readByQuery' => {
            'object' => 'ARINVOICEITEM',
            'fields' => '*',
            'query' => '',
            'pagesize' => '1'
          }
        }
        response_data = call('get_api_response_data_element', function)

        {
          invoice_items: call('format_response',
                              call('parse_xml_to_hash',
                                   'xml' => response_data,
                                   'array_fields' => ['arinvoiceitem'])&.
                                []('arinvoiceitem')) || []
        }
      end
    },

    create_invoices_in_batch: {
      description: "Create <span class='provider'>invoices</span> in a " \
      "batch in <span class='provider'>Sage Intacct (Custom)</span>",
      help: 'Custom fields are supported in this action. Provide a list of ' \
      'records to be created as the input. The maximum number of invoices ' \
      'in a batch is 100.',

      execute: lambda do |connection, input, input_schema, _output_schema|
        input = call('format_input_to_match_schema',
                     'schema' => input_schema,
                     'input' => call('deep_compact', input))
        function = input.dig('operation_element', 'function')
        if (batch_len = function&.length || 0) > 100
          error('The batch size limit for the action is 100. ' \
            "But the current batch has got #{batch_len} invoices.")
        end
        payload = {
          'control' => input['control_element'] || {},
          'operation' => {
            '@transaction' => input.dig('operation_element', 'transaction'),
            'authentication' => {},
            'content' => { 'function' => function }.compact
          }.compact
        }

        call('get_api_response_element',
             'connection' => connection,
             'payload' => payload)
      end,

      input_fields: lambda do |object_definitions|
        object_definitions['invoice_batch_create_input']
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['legacy_batch_create_or_update_response']
      end,

      sample_output: lambda do |_connection, _input|
        {
          operation: {
            result: [{
              status: 'success',
              function: 'create_invoice',
              controlid: 'ID-007',
              key: '1234',
              errormessage: {
                error: [{
                  errorno: 'BL01001973',
                  description2: 'Currently, we can&#039;t create the ' \
                  'transaction',
                  correction: 'Check the transaction for errors or ' \
                  'inconsistencies, then try again.'
                }]
              }
            }]
          }
        }
      end
    },

    # Item
    update_item: {
      description: "Update <span class='provider'>item</span> in " \
      "<span class='provider'>Sage Intacct (Custom)</span>",
      help: 'Custom fields are supported in this action.',

      input_fields: lambda do |object_definitions|
        object_definitions['item_update'].
          ignored('ITEMID').
          required('RECORDNO')
      end,

      execute: lambda do |_connection, input|
        input['customfields'] = [{
          'customfield' => input['customfields']&.map do |key, value|
            {
              'customfieldname' => key,
              'customfieldvalue' => value
            }
          end
        }]
        function = {
          '@controlid' => 'testControlId',
          'update' => { 'ITEM' => input.compact }
        }
        response_data = call('get_api_response_data_element', function)

        call('parse_xml_to_hash',
             'xml' => response_data,
             'array_fields' => ['item'])&.dig('item', 0) || {}
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['item_update'].only('RECORDNO', 'ITEMID')
      end,

      sample_output: lambda do |_connection, _input|
        { 'RECORDNO' => 1234, 'ITEMID' => 'I-007' }
      end
    },

    # MEA Allocation
    search_mea_allocations: {
      title: 'Search MEA allocations',
      description: "Search contract <span class='provider'>MEA allocation" \
      "</span>  in <span class='provider'>Sage Intacct (Custom)</span>",
      help: 'Search will return results that match all your search criteria. ' \
      'Returns a maximum of 100 records. <b>Make sure you have  ' \
      'subscribed for Contract module in your Sage Intacct instance.</b>',
      deprecated: true,

      execute: lambda do |_connection, input|
        input = call('render_date_input', input)
        query = call('format_payload', input)&.
                map { |key, value| "#{key} = '#{value}'" }&.
                smart_join(' AND ') || ''
        function = {
          '@controlid' => 'testControlId',
          'readByQuery' => {
            'object' => 'CONTRACTMEABUNDLE',
            'fields' => '*',
            'query' => query,
            'pagesize' => '100'
          }
        }
        response_data = call('get_api_response_data_element', function)

        {
          mea_bundles: call('format_response',
                            call('parse_xml_to_hash',
                                 'xml' => response_data,
                                 'array_fields' => ['contractmeabundle'])&.
                              []('contractmeabundle')) || []
        }
      end,

      input_fields: lambda do |object_definitions|
        object_definitions['contract_mea_bundle'].
          ignored('WHENCREATED', 'WHENMODIFIED')
      end,

      output_fields: lambda do |object_definitions|
        [{
          name: 'mea_bundles',
          type: 'array',
          of: 'object',
          properties: object_definitions['contract_mea_bundle']
        }]
      end,

      sample_output: lambda do |_connection, _input|
        function = {
          '@controlid' => 'testControlId',
          'readByQuery' => {
            'object' => 'CONTRACTMEABUNDLE',
            'fields' => '*',
            'query' => '',
            'pagesize' => '1'
          }
        }
        response_data = call('get_api_response_data_element', function)

        {
          mea_bundles: call('format_response',
                            call('parse_xml_to_hash',
                                 'xml' => response_data,
                                 'array_fields' => ['contractmeabundle'])&.
                              []('contractmeabundle')) || []
        }
      end
    },

    search_mea_allocations_query: {
      title: 'Search MEA allocations',
      description: "Search contract <span class='provider'>MEA allocation" \
      "</span>  in <span class='provider'>Sage Intacct (Custom)</span>",
      help: 'Search will return results that match all your search criteria. ' \
      'Returns a maximum of 2000 records. <b>Make sure you have  ' \
      'subscribed for Contract module in your Sage Intacct instance.</b>',

      execute: lambda do |_connection, input|
        field_function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'CONTRACTMEABUNDLE' }
        }
        get_fields_response = call('get_api_response_data_element', field_function)
        fields =
          call('parse_xml_to_hash',
               'xml' => get_fields_response,
               'array_fields' => ['Field'])&.
          dig('Type', 'Fields', 'Field')&.pluck('Name')
        select_fields =  { 'field' => input['fields']&.split(',') || fields }
        filter_condition = input['filter_condition'] || 'and'
        query =
          if input['filters'].present?
            if input['filters'].size > 1
              {
                filter_condition =>
                  input['filters']&.map do |filter|
                    { filter['operator'] => { 'field' => filter['field'],
                                              'value' => filter['value']&.split(',') } }
                  end&.each_with_object({}) do |hash, object|
                    hash.each { |key, value| (object[key] ||= []) << value }
                  end
              }
            elsif input['filters'].size == 1
              input['filters']&.map do |filter|
                { filter['operator'] => { 'field' => filter['field'],
                                          'value' => filter['value']&.split(',') } }
              end&.first
            end
          end
        orderby = if input['ordering'].present?
                    { 'order' => { 'field' => input['ordering']['sort_field'],
                                   input['ordering']['sort_order'] => '' } }
                  end
        function = {
          '@controlid' => 'testControlId',
          'query' => {
            'object' => 'CONTRACTMEABUNDLE',
            'select' => select_fields,
            'filter' => query,
            'orderby' => orderby,
            'options' => input['options'],
            'pagesize' => input['pagesize'] || 100,
            'offset' => input['offset'] || 0
          }.compact
        }
        response_data = call('get_api_response_data_element', function)

        {
          mea_bundles: call('format_response',
                            call('parse_xml_to_hash',
                                 'xml' => response_data,
                                 'array_fields' => ['CONTRACTMEABUNDLE'])&.
                            []('CONTRACTMEABUNDLE')) || []
        }
      end,

      input_fields: ->(object_definitions) { object_definitions['contract_mea_bundle_search'] },

      output_fields: lambda do |object_definitions|
        [{
          name: 'mea_bundles',
          label: 'MEA bundles',
          type: 'array',
          of: 'object',
          properties: object_definitions['contract_mea_bundle']
        }]
      end,

      sample_output: lambda do |_connection, _input|
        field_function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'CONTRACTMEABUNDLE' }
        }
        get_fields_response = call('get_api_response_data_element', field_function)
        fields =
          call('parse_xml_to_hash',
               'xml' => get_fields_response,
               'array_fields' => ['Field'])&.
          dig('Type', 'Fields', 'Field')&.pluck('Name')
        function = {
          '@controlid' => 'testControlId',
          'query' => {
            'object' => 'CONTRACTMEABUNDLE',
            'select' => { 'field' => fields },
            'pagesize' => 1
          }.compact
        }
        response_data = call('get_api_response_data_element', function)

        {
          mea_bundles: call('format_response',
                            call('parse_xml_to_hash',
                                 'xml' => response_data,
                                 'array_fields' => ['CONTRACTMEABUNDLE'])&.
                            []('CONTRACTMEABUNDLE')) || []
        }
      end
    },

    create_mea_allocation: {
      title: 'Create MEA allocations',
      description: "Create contract <span class='provider'>MEA allocation" \
      "</span> in <span class='provider'>Sage Intacct (Custom)</span>",

      execute: lambda do |_connection, input|
        input['CONTRACTMEABUNDLEENTRIES'] = {
          'CONTRACTMEABUNDLEENTRY' => input['CONTRACTMEABUNDLEENTRIES']
        }
        function = {
          '@controlid' => 'testControlId',
          'create' => { 'CONTRACTMEABUNDLE' => input }
        }
        response_result = call('get_api_response_result_element', function)

        call('parse_xml_to_hash',
             'xml' => response_result,
             'array_fields' => []) || {}
      end,

      input_fields: lambda do |object_definitions|
        object_definitions['contract_mea_bundle_create']
      end,

      output_fields: lambda do |_object_definitions|
        [{ name: 'RECORDNO', label: 'Record number' }]
      end,

      sample_output: ->(_object_definitions, _input) { { RECORDNO: '12345' } }
    },

    # Purchase Order Transaction
    update_purchase_transaction_header: {
      description: "Update <span class='provider'>purchase transaction " \
      "header</span> in <span class='provider'>Sage Intacct (Custom)</span>",

      execute: lambda do |_connection, input, input_schema, _output_schema|
        function = call('format_input_to_match_schema',
                        'schema' => input_schema,
                        'input' => input).merge('@controlid' => 'testControlId')
        response_result = call('get_api_response_result_element', function)

        call('parse_xml_to_hash',
             'xml' => response_result,
             'array_fields' => []) || {}
      end,

      input_fields: lambda do |object_definitions|
        {
          name: 'update_potransaction',
          label: 'Update PO transaction',
          optional: false,
          type: 'object',
          properties: object_definitions['po_txn_header'].required('@key')
        }
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['legacy_create_or_update_response']
      end,

      sample_output: lambda do |_connection, _input|
        {
          status: 'success',
          function: 'update_potransaction',
          controlid: 'testControlId',
          key: 1234
        }
      end
    },

    add_purchase_transaction_items: {
      description: "Add <span class='provider'>purchase transaction " \
      "items</span> in <span class='provider'>Sage Intacct (Custom)</span>",

      execute: lambda do |_connection, input, input_schema, _output_schema|
        function = call('format_input_to_match_schema',
                        'schema' => input_schema,
                        'input' => input).merge('@controlid' => 'testControlId')
        response_result = call('get_api_response_result_element', function)

        call('parse_xml_to_hash',
             'xml' => response_result,
             'array_fields' => []) || {}
      end,

      input_fields: lambda do |object_definitions|
        {
          name: 'update_potransaction',
          label: 'Update PO transaction',
          optional: false,
          type: 'object',
          properties: object_definitions['po_txn_transitem'].required('@key')
        }
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['legacy_create_or_update_response']
      end,

      sample_output: lambda do |_connection, _input|
        {
          status: 'success',
          function: 'update_potransaction',
          controlid: 'testControlId',
          key: 1234
        }
      end
    },

    update_purchase_transaction_items: {
      description: "Update <span class='provider'>purchase transaction " \
      "items</span> in <span class='provider'>Sage Intacct (Custom)</span>",

      execute: lambda do |_connection, input, input_schema, _output_schema|
        function = call('format_input_to_match_schema',
                        'schema' => input_schema,
                        'input' => input).merge('@controlid' => 'testControlId')
        response_result = call('get_api_response_result_element', function)

        call('parse_xml_to_hash',
             'xml' => response_result,
             'array_fields' => []) || {}
      end,

      input_fields: lambda do |object_definitions|
        {
          name: 'update_potransaction',
          label: 'Update PO transaction',
          optional: false,
          type: 'object',
          properties: object_definitions['po_txn_updatepotransitem'].
            required('@key')
        }
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['legacy_create_or_update_response']
      end,

      sample_output: lambda do |_connection, _input|
        {
          status: 'success',
          function: 'update_potransaction',
          controlid: 'testControlId',
          key: 1234
        }
      end
    },

    search_order_list_query: {
      title: 'Search order entry price list',
      description: "Search <span class='provider'>order entry price list" \
      "</span>  in <span class='provider'>Sage Intacct (Custom)</span>",
      help: 'Search will return results that match all your search criteria. ' \
      'Returns a maximum of 2000 records.',

      execute: lambda do |_connection, input|
        field_function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'SOPRICELIST' }
        }
        get_fields_response = call('get_api_response_data_element', field_function)
        fields =
          call('parse_xml_to_hash',
               'xml' => get_fields_response,
               'array_fields' => ['Field'])&.
          dig('Type', 'Fields', 'Field')&.pluck('Name')
        select_fields =  { 'field' => input['fields']&.split(',') || fields }
        filter_condition = input['filter_condition'] || 'and'
        query =
          if input['filters'].present?
            if input['filters'].size > 1
              {
                filter_condition =>
                  input['filters']&.map do |filter|
                    { filter['operator'] => { 'field' => filter['field'],
                                              'value' => filter['value']&.split(',') } }
                  end&.each_with_object({}) do |hash, object|
                    hash.each { |key, value| (object[key] ||= []) << value }
                  end
              }
            elsif input['filters'].size == 1
              input['filters']&.map do |filter|
                { filter['operator'] => { 'field' => filter['field'],
                                          'value' => filter['value']&.split(',') } }
              end&.first
            end
          end
        orderby = if input['ordering'].present?
                    { 'order' => { 'field' => input['ordering']['sort_field'],
                                   input['ordering']['sort_order'] => '' } }
                  end
        function = {
          '@controlid' => 'testControlId',
          'query' => {
            'object' => 'SOPRICELIST',
            'select' => select_fields,
            'filter' => query,
            'orderby' => orderby,
            'options' => input['options'],
            'pagesize' => input['pagesize'] || 100,
            'offset' => input['offset'] || 0
          }.compact
        }
        response_data = call('get_api_response_data_element', function)

        {
          oe_price_list: call('format_response',
                              call('parse_xml_to_hash',
                                   'xml' => response_data,
                                   'array_fields' => ['SOPRICELIST'])&.[]('SOPRICELIST')) || []
        }
      end,

      input_fields: ->(object_definitions) { object_definitions['oe_price_list_search'] },

      output_fields: lambda do |object_definitions|
        [{
          name: 'oe_price_list',
          label: 'Order entry price list',
          type: 'array',
          of: 'object',
          properties: object_definitions['oe_price_list']
        }]
      end,

      sample_output: lambda do |_connection, _input|
        field_function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'SOPRICELIST' }
        }
        get_fields_response = call('get_api_response_data_element', field_function)
        fields =
          call('parse_xml_to_hash',
               'xml' => get_fields_response,
               'array_fields' => ['Field'])&.
          dig('Type', 'Fields', 'Field')&.pluck('Name')
        function = {
          '@controlid' => 'testControlId',
          'query' => {
            'object' => 'SOPRICELIST',
            'select' => { 'field' => fields },
            'pagesize' => 1
          }.compact
        }
        response_data = call('get_api_response_data_element', function)

        {
          oe_price_list: call('format_response',
                              call('parse_xml_to_hash',
                                   'xml' => response_data,
                                   'array_fields' => ['SOPRICELIST'])&.[]('SOPRICELIST')) || []
        }
      end
    },

    get_order_list: {
      title: 'Get order entry price list entries by price list ID',
      description: "Get <span class='provider'>order entry price list entries</span> in " \
      "<span class='provider'>Sage Intacct (Custom)</span>",

      execute: lambda do |_connection, input|
        function = {
          '@controlid' => 'testControlId',
          'readByQuery' => {
            'object' => 'SOPRICELISTENTRY',
            'fields' => '*',
            'query' => "PRICELISTID = '#{input['PRICELISTID']}'",
            'pagesize' => '2000'
          }
        }
        response_data = call('get_api_response_data_element', function)

        {
          order_list: call('format_response',
                           call('parse_xml_to_hash',
                                'xml' => response_data,
                                'array_fields' => ['sopricelistentry'])&.
                                []('sopricelistentry')) || []
        }
      end,

      input_fields: lambda do |object_definitions|
        object_definitions['order_list_get'].only('PRICELISTID')
      end,

      output_fields: lambda do |object_definitions|
        [{
          name: 'order_list',
          label: 'Price list entries',
          type: 'array',
          of: 'object',
          properties: object_definitions['order_list_get']
        }]
      end,

      sample_output: lambda do |_connection, _input|
        function = {
          '@controlid' => 'testControlId',
          'readByQuery' => {
            'object' => 'SOPRICELISTENTRY',
            'query' => '',
            'fields' => '*',
            'pagesize' => '1'
          }
        }
        response_data = call('get_api_response_data_element', function)

        {
          order_list: call('format_response',
                           call('parse_xml_to_hash',
                                'xml' => response_data,
                                'array_fields' => ['sopricelistentry'])&.
                                []('sopricelistentry')) || []
        }
      end
    },

    search_purchase_list_query: {
      title: 'Search purchasing price list',
      description: "Search <span class='provider'>purchasing price list" \
      "</span>  in <span class='provider'>Sage Intacct (Custom)</span>",
      help: 'Search will return results that match all your search criteria. ' \
      'Returns a maximum of 2000 records.',

      execute: lambda do |_connection, input|
        field_function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'POPRICELIST' }
        }
        get_fields_response = call('get_api_response_data_element', field_function)
        fields =
          call('parse_xml_to_hash',
               'xml' => get_fields_response,
               'array_fields' => ['Field'])&.
          dig('Type', 'Fields', 'Field')&.pluck('Name')
        select_fields =  { 'field' => input['fields']&.split(',') || fields }
        filter_condition = input['filter_condition'] || 'and'
        query =
          if input['filters'].present?
            if input['filters'].size > 1
              {
                filter_condition =>
                  input['filters']&.map do |filter|
                    { filter['operator'] => { 'field' => filter['field'],
                                              'value' => filter['value']&.split(',') } }
                  end&.each_with_object({}) do |hash, object|
                    hash.each { |key, value| (object[key] ||= []) << value }
                  end
              }
            elsif input['filters'].size == 1
              input['filters']&.map do |filter|
                { filter['operator'] => { 'field' => filter['field'],
                                          'value' => filter['value']&.split(',') } }
              end&.first
            end
          end
        orderby = if input['ordering'].present?
                    { 'order' => { 'field' => input['ordering']['sort_field'],
                                   input['ordering']['sort_order'] => '' } }
                  end
        function = {
          '@controlid' => 'testControlId',
          'query' => {
            'object' => 'POPRICELIST',
            'select' => select_fields,
            'filter' => query,
            'orderby' => orderby,
            'options' => input['options'],
            'pagesize' => input['pagesize'] || 100,
            'offset' => input['offset'] || 0
          }.compact
        }
        response_data = call('get_api_response_data_element', function)

        {
          purchasing_price_list: call('format_response',
                                      call('parse_xml_to_hash',
                                           'xml' => response_data,
                                           'array_fields' => ['POPRICELIST'])&.
                                           []('POPRICELIST')) || []
        }
      end,

      input_fields: ->(object_definitions) { object_definitions['purchase_list_search'] },

      output_fields: lambda do |object_definitions|
        [{
          name: 'purchasing_price_list',
          label: 'Purchasing price list',
          type: 'array',
          of: 'object',
          properties: object_definitions['purchase_price_list']
        }]
      end,

      sample_output: lambda do |_connection, _input|
        field_function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'POPRICELIST' }
        }
        get_fields_response = call('get_api_response_data_element', field_function)
        fields =
          call('parse_xml_to_hash',
               'xml' => get_fields_response,
               'array_fields' => ['Field'])&.
          dig('Type', 'Fields', 'Field')&.pluck('Name')
        function = {
          '@controlid' => 'testControlId',
          'query' => {
            'object' => 'POPRICELIST',
            'select' => { 'field' => fields },
            'pagesize' => 1
          }.compact
        }
        response_data = call('get_api_response_data_element', function)

        {
          purchasing_price_list: call('format_response',
                                      call('parse_xml_to_hash',
                                           'xml' => response_data,
                                           'array_fields' => ['POPRICELIST'])&.
                                           []('POPRICELIST')) || []
        }
      end
    },

    get_purchase_list: {
      title: 'Get purchasing price list entries by price list ID',
      description: "Get <span class='provider'>purchasing price list entries</span> in " \
      "<span class='provider'>Sage Intacct (Custom)</span>",

      execute: lambda do |_connection, input|
        function = {
          '@controlid' => 'testControlId',
          'readByQuery' => {
            'object' => 'POPRICELISTENTRY',
            'fields' => '*',
            'query' => "PRICELISTID = '#{input['PRICELISTID']}'",
            'pagesize' => '2000'
          }
        }
        response_data = call('get_api_response_data_element', function)

        {
          order_list: call('format_response',
                           call('parse_xml_to_hash',
                                'xml' => response_data,
                                'array_fields' => ['popricelistentry'])&.
                                []('popricelistentry')) || []
        }
      end,

      input_fields: lambda do |object_definitions|
        object_definitions['purchase_list_get'].only('PRICELISTID')
      end,

      output_fields: lambda do |object_definitions|
        [{
          name: 'order_list',
          label: 'Price list entries',
          type: 'array',
          of: 'object',
          properties: object_definitions['order_list_get']
        }]
      end,

      sample_output: lambda do |_connection, _input|
        function = {
          '@controlid' => 'testControlId',
          'readByQuery' => {
            'object' => 'POPRICELISTENTRY',
            'query' => '',
            'fields' => '*',
            'pagesize' => '1'
          }
        }
        response_data = call('get_api_response_data_element', function)

        {
          order_list: call('format_response',
                           call('parse_xml_to_hash',
                                'xml' => response_data,
                                'array_fields' => ['popricelistentry'])&.
                                []('popricelistentry')) || []
        }
      end
    },

    # Update Stat GL Entry
    update_stat_gl_entry: {
      title: 'Update statistical journal entry',
      description: "Update <span class='provider'>statistical journal entry" \
      "</span> in <span class='provider'>Sage Intacct (Custom)</span>",
      help: 'Custom fields are supported in this action.',

      execute: lambda do |_connection, input|
        function = {
          '@controlid' => 'testControlId',
          'update' => { 'GLBATCH' => input }
        }
        response_data = call('get_api_response_data_element', function)

        call('parse_xml_to_hash',
             'xml' => response_data,
             'array_fields' => [])&.dig('glbatch', 0) || {}
      end,

      input_fields: lambda do |object_definitions|
        object_definitions['stat_gl_batch'].
          required('RECORDNO', 'BATCH_DATE', 'BATCH_TITLE', 'ENTRIES')
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['update_response']
      end,

      sample_output: ->(_connection, _input) { { 'RECORDNO' => 1234 } }
    },

    # Task
    search_tasks: {
      subtitle: 'Search tasks in Sage Intacct (Custom)',
      description: "Search <span class='provider'>tasks</span>  in " \
      "<span class='provider'>Sage Intacct (Custom)</span>",
      help: 'Search will return results that match all your search criteria. ' \
      'Returns a maximum of 100 records.',
      deprecated: true,

      input_fields: lambda do |object_definitions|
        object_definitions['task'].
          ignored('PROJECTBEGINDATE', 'PROJECTENDDATE', 'CUSTOMERKEY',
                  'CUSTOMERID', 'CUSTOMERNAME', 'WHENCREATED', 'WHENMODIFIED')
      end,

      execute: lambda do |_connection, input, e_i_s|
        date_fields = e_i_s.where(control_type: 'date').pluck(:name)
        date_time_fields = e_i_s.where(control_type: 'date_time').pluck(:name)
        query = input.map do |key, value|
          if date_fields.include?(key)
            { 'field' => key, 'value' => value&.to_date&.strftime('%m/%d/%Y') }
          elsif date_time_fields.include?(key)
            { 'field' => key, 'value' => value&.to_date&.strftime('%m/%d/%Y %H:%M:%S') }
          else
            { 'field' => key, 'value' => value }
          end
        end
        filter = if query.length > 1
                   { 'and' => { 'equalto' => query } }
                 else
                   { 'equalto' => query }
                 end
        function = {
          '@controlid' => 'testControlId',
          'query' => {
            'object' => 'TASK',
            'select' => { 'field' => e_i_s.pluck(:name) },
            'filter' => filter,
            'pagesize' => '100'
          }
        }
        response_data = call('get_api_response_data_element', function)
        { tasks: call('format_response',
                      call('parse_xml_to_hash',
                           'xml' => response_data,
                           'array_fields' => ['TASK'])&.[]('TASK')) }
      end,

      output_fields: lambda do |object_definitions|
        [{ name: 'tasks', type: 'array', of: 'object',
           properties: object_definitions['task'] }]
      end,

      sample_output: lambda do |_connection, _input|
        function = {
          '@controlid' => 'testControlId',
          'query' => {
            'object' => 'TASK',
            'select' => {
              'field' => %w[TASKID RECORDNO NAME DESCRIPTION PROJECTID WHENCREATED WHENMODIFIED]
            },
            'pagesize' => '1'
          }
        }
        response_data = call('get_api_response_data_element', function)
        { tasks: call('format_response',
                      call('parse_xml_to_hash',
                           'xml' => response_data,
                           'array_fields' => ['TASK']))&.dig('TASK', 0) }
      end
    },

    search_tasks_query: {
      title: 'Search tasks',
      description: "Search <span class='provider'>Tasks</span> in " \
      "<span class='provider'>Sage Intacct (Custom)</span>",
      help: 'Search will return results that match all your search criteria. ' \
      'Returns a maximum of 2000 records.',

      execute: lambda do |_connection, input|
        field_function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'TASK' }
        }
        get_fields_response = call('get_api_response_data_element', field_function)
        fields =
          call('parse_xml_to_hash',
               'xml' => get_fields_response,
               'array_fields' => ['Field'])&.
          dig('Type', 'Fields', 'Field')&.pluck('Name')
        select_fields =  { 'field' => input['fields']&.split(',') || fields }
        filter_condition = input['filter_condition'] || 'and'
        query =
          if input['filters'].present?
            if input['filters'].size > 1
              {
                filter_condition =>
                  input['filters']&.map do |filter|
                    { filter['operator'] => { 'field' => filter['field'],
                                              'value' => filter['value']&.split(',') } }
                  end&.each_with_object({}) do |hash, object|
                    hash.each { |key, value| (object[key] ||= []) << value }
                  end
              }
            elsif input['filters'].size == 1
              input['filters']&.map do |filter|
                { filter['operator'] => { 'field' => filter['field'],
                                          'value' => filter['value']&.split(',') } }
              end&.first
            end
          end
        orderby = if input['ordering'].present?
                    { 'order' => { 'field' => input['ordering']['sort_field'],
                                   input['ordering']['sort_order'] => '' } }
                  end
        function = {
          '@controlid' => 'testControlId',
          'query' => {
            'object' => 'TASK',
            'select' => select_fields,
            'filter' => query,
            'orderby' => orderby,
            'options' => input['options'],
            'pagesize' => input['pagesize'] || 100,
            'offset' => input['offset'] || 0
          }.compact
        }
        response_data = call('get_api_response_data_element', function)

        {
          tasks: call('format_response',
                      call('parse_xml_to_hash',
                           'xml' => response_data,
                           'array_fields' => ['TASK'])&.
                      []('TASK')) || []
        }
      end,

      input_fields: ->(object_definitions) { object_definitions['task_search'] },

      output_fields: lambda do |object_definitions|
        [{
          name: 'tasks',
          type: 'array',
          of: 'object',
          properties: object_definitions['task']
        }]
      end,

      sample_output: lambda do |_connection, _input|
        field_function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'TASK' }
        }
        get_fields_response = call('get_api_response_data_element', field_function)
        fields =
          call('parse_xml_to_hash',
               'xml' => get_fields_response,
               'array_fields' => ['Field'])&.
          dig('Type', 'Fields', 'Field')&.pluck('Name')
        function = {
          '@controlid' => 'testControlId',
          'query' => {
            'object' => 'TASK',
            'select' => { 'field' => fields },
            'pagesize' => 1
          }.compact
        }
        response_data = call('get_api_response_data_element', function)

        {
          tasks: call('format_response',
                      call('parse_xml_to_hash',
                           'xml' => response_data,
                           'array_fields' => ['TASK'])&.
                      []('TASK')) || []
        }
      end
    },

    get_task: {
      title: 'Get task by record number',
      subtitle: 'Get task by record number in Sage Intacct (Custom)',
      description: "Get <span class='provider'>task</span> by record " \
      "number in <span class='provider'>Sage Intacct (Custom)</span>",

      execute: lambda do |_connection, input|
        function = {
          '@controlid' => 'testControlId',
          'read' => {
            'object' => 'TASK',
            'keys' => input['keys'],
            'fields' => '*'
          }
        }
        response_data = call('get_api_response_data_element', function)
        call('format_response',
             call('parse_xml_to_hash',
                  'xml' => response_data,
                  'array_fields' => ['TASK']))&.dig('TASK', 0)
      end,

      input_fields: lambda do |_object_definitions|
        [{ name: 'keys', label: 'Record number', optional: false,
           type: 'integer', control_type: 'integer' }]
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['task_get_output'].
          concat([
                   {
                     name: 'PRODUCTIONUNITESTIMATE',
                     label: 'Production unit estimate'
                   },
                   {
                     name: 'ORIGINALPRODUCTIONUNITS',
                     label: 'Original estimated production units'
                   },
                   {
                     name: 'REVISIONPRODUCTIONUNITS',
                     label: 'Revision estimated production units'
                   },
                   {
                     name: 'APPROVEDCHANGEPRODUCTIONUNITS',
                     label: 'Approved change estimated production units'
                   },
                   {
                     name: 'PENDINGCHANGEPRODUCTIONUNITS',
                     label: 'Pending change estimated production units'
                   },
                   {
                     name: 'FORECASTPRODUCTIONUNITS',
                     label: 'Forecast estimated production units'
                   },
                   {
                     name: 'OTHERPRODUCTIONUNITS',
                     label: 'Other estimated production units'
                   },
                   { name: 'ROOTPARENTNAME', label: 'Root task name' },
                   { name: 'ROOTPARENTKEY', label: 'Root task key' }
                 ])
      end,

      sample_output: lambda do |_connection, _input|
        function = {
          '@controlid' => 'testControlId',
          'query' => {
            'object' => 'TASK',
            'select' => {
              'field' => %w[TASKID RECORDNO NAME DESCRIPTION PROJECTID WHENCREATED WHENMODIFIED]
            },
            'pagesize' => '1'
          }
        }
        response_data = call('get_api_response_data_element', function)

        call('format_response',
             call('parse_xml_to_hash',
                  'xml' => response_data,
                  'array_fields' => ['TASK']))&.dig('TASK', 0)
      end
    },

    create_task: {
      description: "Create <span class='provider'>task</span> in " \
      "<span class='provider'>Sage Intacct (Custom)</span>",
      help: 'Custom fields are supported in this action.',

      input_fields: lambda do |object_definitions|
        object_definitions['task_create'].
          ignored('TASKSTATUS').
          concat([{
                   name: 'TASKSTATUS',
                   label: 'Task status',
                   optional: false,
                   control_type: 'select',
                   pick_list: 'task_statuses',
                   toggle_hint: 'Select from list',
                   toggle_field: {
                     name: 'TASKSTATUS',
                     label: 'Task status',
                     type: 'string',
                     control_type: 'text',
                     optional: false,
                     toggle_hint: 'Use custom value',
                     hint: 'Allowed values are: <b>Not Started</b>, ' \
                      '<b>Planned</b>, <b>In Progress</b>, <b>Completed</b>, ' \
                      '<b>On Hold</b>'
                   }
                 }]).
          required('NAME')
      end,

      execute: lambda do |_connection, input|
        function = {
          '@controlid' => 'testControlId',
          'create' => { 'TASK' => input }
        }
        response_data = call('get_api_response_data_element', function)
        call('parse_xml_to_hash',
             'xml' => response_data,
             'array_fields' => ['task'])&.dig('task', 0)
      end,

      output_fields: lambda do |_object_definitions|
        [{ name: 'RECORDNO', label: 'Record number', type: 'integer' }]
      end,

      sample_output: lambda do |_connection, _input|
        { RECORDNO: 1234 }
      end
    },

    update_task: {
      description: "Update <span class='provider'>task</span> in " \
      "<span class='provider'>Sage Intacct (Custom)</span>",
      help: 'Custom fields are supported in this action.',

      input_fields: lambda do |object_definitions|
        [{
          name: 'RECORDNO',
          label: 'Record number',
          optional: false,
          type: 'integer',
          control_type: 'integer'
        }].concat(object_definitions['task_create'].
          ignored('TASKID', 'PROJECTID', 'STANDARDTASKID', 'PRODUCTIONUNITDESC'))
      end,

      execute: lambda do |_connection, input|
        function = {
          '@controlid' => 'testControlId',
          'update' => { 'TASK' => input }
        }
        response_data = call('get_api_response_data_element', function)
        call('parse_xml_to_hash',
             'xml' => response_data,
             'array_fields' => ['task'])&.dig('task', 0)
      end,

      output_fields: lambda do |_object_definitions|
        [{ name: 'RECORDNO', label: 'Record number', type: 'integer' }]
      end,

      sample_output: lambda do |_connection, _input|
        { RECORDNO: 1234 }
      end
    },

    delete_task: {
      description: "Delete <span class='provider'>task(s)</span> in " \
      "<span class='provider'>Sage Intacct (Custom)</span>",

      input_fields: lambda do |_object_definitions|
        [{ name: 'keys', label: 'Record number', optional: false, hint: 'Multiple ' \
          'record numbers can applied by providing values separated by comma' }]
      end,

      execute: lambda do |_connection, input|
        function = {
          '@controlid' => 'testControlId',
          'delete' => { 'object' => 'TASK', 'keys' => input['keys'] }
        }
        response_data = call('get_api_response_result_element', function)
        { status: call('parse_xml_to_hash',
                       'xml' => response_data,
                       'array_fields' => [])['status'] }
      end,

      output_fields: ->(_object_definitions) { [{ name: 'status' }] },

      sample_output: ->(_connection, _input) { { status: 'success' } }
    },

    # Timesheet
    create_timesheet: {
      description: "Create <span class='provider'>timesheet</span> in " \
      "<span class='provider'>Sage Intacct (Custom)</span>",

      execute: lambda do |_connection, input|
        function = {
          '@controlid' => 'testControlId',
          'create' => { 'TIMESHEET' => input }
        }
        response_data = call('get_api_response_data_element', function)

        call('parse_xml_to_hash',
             'xml' => response_data,
             'array_fields' => ['TIMESHEETENTRY'])&.dig('timesheet') || {}
      end,

      input_fields: lambda do |object_definitions|
        object_definitions['timesheet_create'].
          required('EMPLOYEEID', 'BEGINDATE', 'TIMESHEETENTRIES')
      end,

      output_fields: lambda do |_object_definitions|
        [{ name: 'RECORDNO', label: 'Record number' }]
      end,

      sample_output: lambda do |_connection, _input|
        { 'RECORDNO' => 1234 }
      end
    },

    update_timesheet: {
      description: "Update <span class='provider'>timesheet</span> in " \
      "<span class='provider'>Sage Intacct (Custom)</span>",
      help: 'Updates an existing timesheet. This action will completely ' \
      'replace the existing timesheet and all of its entries.',

      execute: lambda do |_connection, input|
        function = {
          '@controlid' => 'testControlId',
          'update' => { 'TIMESHEET' => input }
        }
        response_data = call('get_api_response_data_element', function)

        call('parse_xml_to_hash',
             'xml' => response_data,
             'array_fields' => ['TIMESHEETENTRY'])&.dig('timesheet') || {}
      end,

      input_fields: lambda do |object_definitions|
        [{ name: 'RECORDNO', label: 'Record number', optional: false }].
          concat(object_definitions['timesheet_create'])
      end,

      output_fields: lambda do |_object_definitions|
        [{ name: 'RECORDNO', label: 'Record number' }]
      end,

      sample_output: lambda do |_connection, _input|
        { 'RECORDNO' => 1234 }
      end
    },

    get_timesheet: {
      title: 'Get timesheet by record number',
      description: "Get <span class='provider'>timesheet</span> by record " \
      "number in <span class='provider'>Sage Intacct (Custom)</span>",

      execute: lambda do |_connection, input|
        function = {
          '@controlid' => 'testControlId',
          'readByQuery' => {
            'object' => 'TIMESHEET',
            'fields' => '*',
            'query' => "RECORDNO = '#{input['RECORDNO']}'",
            'pagesize' => '1'
          }
        }
        response_data = call('get_api_response_data_element', function)

        call('format_response',
             call('parse_xml_to_hash',
                  'xml' => response_data,
                  'array_fields' => ['timesheet'])&.dig('timesheet', 0)) || {}
      end,

      input_fields: lambda do |_object_definitions|
        [{ name: 'RECORDNO', label: 'Record number', optional: false }]
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['timesheet']
      end,

      sample_output: lambda do |_connection, _input|
        function = {
          '@controlid' => 'testControlId',
          'readByQuery' => {
            'object' => 'TIMESHEET',
            'query' => '',
            'fields' => '*',
            'pagesize' => '1'
          }
        }
        response_data = call('get_api_response_data_element', function)

        call('format_response',
             call('parse_xml_to_hash',
                  'xml' => response_data,
                  'array_fields' => ['timesheet'])&.dig('timesheet', 0)) || {}
      end
    },

    search_timesheets: {
      title: 'Search timesheets',
      description: "Search <span class='provider'>timesheets</span>  in " \
      "<span class='provider'>Sage Intacct (Custom)</span>",
      help: 'Search will return results that match all your search criteria. ' \
      'Returns a maximum of 100 records.',
      deprecated: true,

      execute: lambda do |_connection, input|
        input = call('render_date_input', input)
        query = call('format_payload', input)&.
                map { |key, value| "#{key} = '#{value}'" }&.
                smart_join(' and ') || ''
        function = {
          '@controlid' => 'testControlId',
          'readByQuery' => {
            'object' => 'TIMESHEET',
            'fields' => '*',
            'query' => query,
            'pagesize' => '100'
          }
        }
        response_data = call('get_api_response_data_element', function)

        {
          timesheets: call('format_response',
                           call('parse_xml_to_hash',
                                'xml' => response_data,
                                'array_fields' => ['timesheet'])&.[]('timesheet')) || []
        }
      end,

      input_fields: lambda do |object_definitions|
        object_definitions['timesheet'].ignored('WHENCREATED', 'WHENMODIFIED')
      end,

      output_fields: lambda do |object_definitions|
        [{ name: 'timesheets', type: 'array', of: 'object',
           properties: object_definitions['timesheet'] }]
      end,

      sample_output: lambda do |_connection, _input|
        function = {
          '@controlid' => 'testControlId',
          'readByQuery' => {
            'object' => 'TIMESHEET',
            'fields' => '*',
            'query' => '',
            'pagesize' => '1'
          }
        }
        response_data = call('get_api_response_data_element', function)

        {
          timesheets: call('format_response',
                           call('parse_xml_to_hash',
                                'xml' => response_data,
                                'array_fields' => ['timesheet'])&.[]('timesheet')) || []
        }
      end
    },

    search_timesheets_query: {
      title: 'Search timesheets',
      description: "Search <span class='provider'>Timesheets</span> in " \
      "<span class='provider'>Sage Intacct (Custom)</span>",
      help: 'Search will return results that match all your search criteria. ' \
      'Returns a maximum of 2000 records.',

      execute: lambda do |_connection, input|
        field_function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'TIMESHEET' }
        }
        get_fields_response = call('get_api_response_data_element', field_function)
        fields =
          call('parse_xml_to_hash',
               'xml' => get_fields_response,
               'array_fields' => ['Field'])&.
          dig('Type', 'Fields', 'Field')&.pluck('Name')
        select_fields =  { 'field' => input['fields']&.split(',') || fields }
        filter_condition = input['filter_condition'] || 'and'
        query =
          if input['filters'].present?
            if input['filters'].size > 1
              {
                filter_condition =>
                  input['filters']&.map do |filter|
                    { filter['operator'] => { 'field' => filter['field'],
                                              'value' => filter['value']&.split(',') } }
                  end&.each_with_object({}) do |hash, object|
                    hash.each { |key, value| (object[key] ||= []) << value }
                  end
              }
            elsif input['filters'].size == 1
              input['filters']&.map do |filter|
                { filter['operator'] => { 'field' => filter['field'],
                                          'value' => filter['value']&.split(',') } }
              end&.first
            end
          end
        orderby = if input['ordering'].present?
                    { 'order' => { 'field' => input['ordering']['sort_field'],
                                   input['ordering']['sort_order'] => '' } }
                  end
        function = {
          '@controlid' => 'testControlId',
          'query' => {
            'object' => 'TIMESHEET',
            'select' => select_fields,
            'filter' => query,
            'orderby' => orderby,
            'options' => input['options'],
            'pagesize' => input['pagesize'] || 100,
            'offset' => input['offset'] || 0
          }.compact
        }
        response_data = call('get_api_response_data_element', function)

        {
          timesheets: call('format_response',
                           call('parse_xml_to_hash',
                                'xml' => response_data,
                                'array_fields' => ['TIMESHEET'])&.
                           []('TIMESHEET')) || []
        }
      end,

      input_fields: ->(object_definitions) { object_definitions['timesheet_search'] },

      output_fields: lambda do |object_definitions|
        [{
          name: 'timesheets',
          type: 'array',
          of: 'object',
          properties: object_definitions['timesheet']
        }]
      end,

      sample_output: lambda do |_connection, _input|
        field_function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'TIMESHEET' }
        }
        get_fields_response = call('get_api_response_data_element', field_function)
        fields =
          call('parse_xml_to_hash',
               'xml' => get_fields_response,
               'array_fields' => ['Field'])&.
          dig('Type', 'Fields', 'Field')&.pluck('Name')
        function = {
          '@controlid' => 'testControlId',
          'query' => {
            'object' => 'TIMESHEET',
            'select' => { 'field' => fields },
            'pagesize' => 1
          }.compact
        }
        response_data = call('get_api_response_data_element', function)

        {
          timesheets: call('format_response',
                           call('parse_xml_to_hash',
                                'xml' => response_data,
                                'array_fields' => ['TIMESHEET'])&.
                           []('TIMESHEET')) || []
        }
      end
    },

    search_timesheet_entries: {
      title: 'Search timesheet entries',
      description: "Search <span class='provider'>timesheet entries</span>  in " \
      "<span class='provider'>Sage Intacct (Custom)</span>",
      help: 'Search will return results that match all your search criteria. ' \
      'Returns a maximum of 100 records.',
      deprecated: true,

      execute: lambda do |_connection, input|
        input = call('render_date_input', input)
        query = call('format_payload', input)&.
                map { |key, value| "#{key} = '#{value}'" }&.
                smart_join(' and ') || ''
        function = {
          '@controlid' => 'testControlId',
          'readByQuery' => {
            'object' => 'TIMESHEETENTRY',
            'fields' => '*',
            'query' => query,
            'pagesize' => '100'
          }
        }
        response_data = call('get_api_response_data_element', function)

        {
          timesheet_entries: call('format_response',
                                  call('parse_xml_to_hash',
                                       'xml' => response_data,
                                       'array_fields' => ['timesheetentry'])&.
                                     []('timesheetentry')) || []
        }
      end,

      input_fields: lambda do |object_definitions|
        object_definitions['timesheet_entry'].
          ignored('WHENCREATED', 'WHENMODIFIED')
      end,

      output_fields: lambda do |object_definitions|
        [{ name: 'timesheet_entries', type: 'array', of: 'object',
           properties: object_definitions['timesheet_entry'] }]
      end,

      sample_output: lambda do |_connection, _input|
        function = {
          '@controlid' => 'testControlId',
          'readByQuery' => {
            'object' => 'TIMESHEETENTRY',
            'fields' => '*',
            'query' => '',
            'pagesize' => '1'
          }
        }
        response_data = call('get_api_response_data_element', function)

        {
          timesheet_entries: call('format_response',
                                  call('parse_xml_to_hash',
                                       'xml' => response_data,
                                       'array_fields' => ['timesheetentry'])&.
                                     []('timesheetentry')) || []
        }
      end
    },

    search_timesheet_entries_query: {
      title: 'Search timesheet entries',
      description: "Search <span class='provider'>Timesheet entries</span> in " \
      "<span class='provider'>Sage Intacct (Custom)</span>",
      help: 'Search will return results that match all your search criteria. ' \
      'Returns a maximum of 2000 records.',

      execute: lambda do |_connection, input|
        field_function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'TIMESHEETENTRY' }
        }
        get_fields_response = call('get_api_response_data_element', field_function)
        fields =
          call('parse_xml_to_hash',
               'xml' => get_fields_response,
               'array_fields' => ['Field'])&.
          dig('Type', 'Fields', 'Field')&.pluck('Name')
        select_fields =  { 'field' => input['fields']&.split(',') || fields }
        filter_condition = input['filter_condition'] || 'and'
        query =
          if input['filters'].present?
            if input['filters'].size > 1
              {
                filter_condition =>
                  input['filters']&.map do |filter|
                    { filter['operator'] => { 'field' => filter['field'],
                                              'value' => filter['value']&.split(',') } }
                  end&.each_with_object({}) do |hash, object|
                    hash.each { |key, value| (object[key] ||= []) << value }
                  end
              }
            elsif input['filters'].size == 1
              input['filters']&.map do |filter|
                { filter['operator'] => { 'field' => filter['field'],
                                          'value' => filter['value']&.split(',') } }
              end&.first
            end
          end
        orderby = if input['ordering'].present?
                    { 'order' => { 'field' => input['ordering']['sort_field'],
                                   input['ordering']['sort_order'] => '' } }
                  end
        function = {
          '@controlid' => 'testControlId',
          'query' => {
            'object' => 'TIMESHEETENTRY',
            'select' => select_fields,
            'filter' => query,
            'orderby' => orderby,
            'options' => input['options'],
            'pagesize' => input['pagesize'] || 100,
            'offset' => input['offset'] || 0
          }.compact
        }
        response_data = call('get_api_response_data_element', function)

        {
          timesheet_entries: call('format_response',
                                  call('parse_xml_to_hash',
                                       'xml' => response_data,
                                       'array_fields' => ['TIMESHEETENTRY'])&.
                                  []('TIMESHEETENTRY')) || []
        }
      end,

      input_fields: ->(object_definitions) { object_definitions['timesheet_entry_search'] },

      output_fields: lambda do |object_definitions|
        [{
          name: 'timesheet_entries',
          type: 'array',
          of: 'object',
          properties: object_definitions['timesheet_entry']
        }]
      end,

      sample_output: lambda do |_connection, _input|
        field_function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'TIMESHEETENTRY' }
        }
        get_fields_response = call('get_api_response_data_element', field_function)
        fields =
          call('parse_xml_to_hash',
               'xml' => get_fields_response,
               'array_fields' => ['Field'])&.
          dig('Type', 'Fields', 'Field')&.pluck('Name')
        function = {
          '@controlid' => 'testControlId',
          'query' => {
            'object' => 'TIMESHEETENTRY',
            'select' => { 'field' => fields },
            'pagesize' => 1
          }.compact
        }
        response_data = call('get_api_response_data_element', function)

        {
          timesheet_entries: call('format_response',
                                  call('parse_xml_to_hash',
                                       'xml' => response_data,
                                       'array_fields' => ['TIMESHEETENTRY'])&.
                                  []('TIMESHEETENTRY')) || []
        }
      end
    },

    get_timesheet_entry: {
      title: 'Get timesheet entry by record number',
      description: "Get <span class='provider'>timesheet entry</span> by record " \
      "number in <span class='provider'>Sage Intacct (Custom)</span>",

      execute: lambda do |_connection, input|
        function = {
          '@controlid' => 'testControlId',
          'readByQuery' => {
            'object' => 'TIMESHEETENTRY',
            'fields' => '*',
            'query' => "RECORDNO = '#{input['RECORDNO']}'",
            'pagesize' => '1'
          }
        }
        response_data = call('get_api_response_data_element', function)

        call('format_response',
             call('parse_xml_to_hash',
                  'xml' => response_data,
                  'array_fields' => ['timesheetentry'])&.dig('timesheetentry', 0)) || {}
      end,

      input_fields: lambda do |_object_definitions|
        [{ name: 'RECORDNO', label: 'Record number', optional: false }]
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['timesheet_entry']
      end,

      sample_output: lambda do |_connection, _input|
        function = {
          '@controlid' => 'testControlId',
          'readByQuery' => {
            'object' => 'TIMESHEETENTRY',
            'query' => '',
            'fields' => '*',
            'pagesize' => '1'
          }
        }
        response_data = call('get_api_response_data_element', function)

        call('format_response',
             call('parse_xml_to_hash',
                  'xml' => response_data,
                  'array_fields' => ['timesheetentry'])&.
                  dig('timesheetentry', 0)) || {}
      end
    },

    # Vendor
    search_vendors: {
      title: 'Search vendors',
      description: "Search <span class='provider'>Vendors</span>  in " \
      "<span class='provider'>Sage Intacct (Custom)</span>",
      help: 'Search will return results that match all your search criteria. ' \
      'Returns a maximum of 100 records.',
      deprecated: true,

      execute: lambda do |_connection, input|
        input = call('render_date_input', input)
        query = call('format_payload', input)&.
                map { |key, value| "#{key} = '#{value}'" }&.
                smart_join(' and ') || ''
        function = {
          '@controlid' => 'testControlId',
          'readByQuery' => {
            'object' => 'VENDOR',
            'fields' => '*',
            'query' => query,
            'pagesize' => '100'
          }
        }
        response_data = call('get_api_response_data_element', function)

        {
          vendors: call('format_response',
                        call('parse_xml_to_hash',
                             'xml' => response_data,
                             'array_fields' => ['vendor'])&.
                        []('vendor')) || []
        }
      end,

      input_fields: ->(object_definitions) { object_definitions['vendor'] },

      output_fields: lambda do |object_definitions|
        [{
          name: 'vendors',
          type: 'array',
          of: 'object',
          properties: object_definitions['vendor']
        }]
      end,

      sample_output: lambda do |_connection, _input|
        function = {
          '@controlid' => 'testControlId',
          'readByQuery' => {
            'object' => 'VENDOR',
            'fields' => '*',
            'query' => '',
            'pagesize' => '1'
          }
        }
        response_data = call('get_api_response_data_element', function)

        {
          vendors: call('format_api_output_field_names',
                        call('parse_xml_to_hash',
                             'xml' => response_data,
                             'array_fields' => ['vendor'])&.
                        []('vendor')) || []
        }
      end
    },

    search_vendors_query: {
      title: 'Search vendors',
      description: "Search <span class='provider'>Vendors</span> in " \
      "<span class='provider'>Sage Intacct (Custom)</span>",
      help: 'Search will return results that match all your search criteria. ' \
      'Returns a maximum of 2000 records.',

      execute: lambda do |_connection, input|
        field_function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'VENDOR' }
        }
        get_fields_response = call('get_api_response_data_element', field_function)
        fields =
          call('parse_xml_to_hash',
               'xml' => get_fields_response,
               'array_fields' => ['Field'])&.
          dig('Type', 'Fields', 'Field')&.pluck('Name')
        select_fields =  { 'field' => input['fields']&.split(',') || fields }
        filter_condition = input['filter_condition'] || 'and'
        query =
          if input['filters'].present?
            if input['filters'].size > 1
              {
                filter_condition =>
                  input['filters']&.map do |filter|
                    { filter['operator'] => { 'field' => filter['field'],
                                              'value' => filter['value']&.split(',') } }
                  end&.each_with_object({}) do |hash, object|
                    hash.each { |key, value| (object[key] ||= []) << value }
                  end
              }
            elsif input['filters'].size == 1
              input['filters']&.map do |filter|
                { filter['operator'] => { 'field' => filter['field'],
                                          'value' => filter['value']&.split(',') } }
              end&.first
            end
          end
        orderby = if input['ordering'].present?
                    { 'order' => { 'field' => input['ordering']['sort_field'],
                                   input['ordering']['sort_order'] => '' } }
                  end
        function = {
          '@controlid' => 'testControlId',
          'query' => {
            'object' => 'VENDOR',
            'select' => select_fields,
            'filter' => query,
            'orderby' => orderby,
            'options' => input['options'],
            'pagesize' => input['pagesize'] || 100,
            'offset' => input['offset'] || 0
          }.compact
        }
        response_data = call('get_api_response_data_element', function)

        {
          vendors: call('format_response',
                        call('parse_xml_to_hash',
                             'xml' => response_data,
                             'array_fields' => ['VENDOR'])&.
                        []('VENDOR')) || []
        }
      end,

      input_fields: ->(object_definitions) { object_definitions['vendor_search'] },

      output_fields: lambda do |object_definitions|
        [{
          name: 'vendors',
          type: 'array',
          of: 'object',
          properties: object_definitions['vendor']
        }]
      end,

      sample_output: lambda do |_connection, _input|
        field_function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'VENDOR' }
        }
        get_fields_response = call('get_api_response_data_element', field_function)
        fields =
          call('parse_xml_to_hash',
               'xml' => get_fields_response,
               'array_fields' => ['Field'])&.
          dig('Type', 'Fields', 'Field')&.pluck('Name')
        function = {
          '@controlid' => 'testControlId',
          'query' => {
            'object' => 'VENDOR',
            'select' => { 'field' => fields },
            'pagesize' => 1
          }.compact
        }
        response_data = call('get_api_response_data_element', function)

        {
          vendors: call('format_response',
                        call('parse_xml_to_hash',
                             'xml' => response_data,
                             'array_fields' => ['VENDOR'])&.
                        []('VENDOR')) || []
        }
      end
    },

    # Purchasing transaction
    search_purchasing_transactions_query: {
      title: 'Search purchasing transactions',
      description: "Search <span class='provider'>Purchasing transactions</span> in " \
      "<span class='provider'>Sage Intacct (Custom)</span>",
      help: 'Search will return results that match all your search criteria. ' \
      'Returns a maximum of 2000 records.',

      execute: lambda do |_connection, input|
        field_function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'PODOCUMENT' }
        }
        get_fields_response = call('get_api_response_data_element', field_function)
        fields =
          call('parse_xml_to_hash',
               'xml' => get_fields_response,
               'array_fields' => ['Field'])&.
          dig('Type', 'Fields', 'Field')&.pluck('Name')&.
          reject { |name| %w[ENABLEDOCCHANGE].include?(name) }
        select_fields =  { 'field' => input['fields']&.split(',') || fields }
        filter_condition = input['filter_condition'] || 'and'
        query =
          if input['filters'].present?
            if input['filters'].size > 1
              {
                filter_condition =>
                  input['filters']&.map do |filter|
                    { filter['operator'] => { 'field' => filter['field'],
                                              'value' => filter['value']&.split(',') } }
                  end&.each_with_object({}) do |hash, object|
                    hash.each { |key, value| (object[key] ||= []) << value }
                  end
              }
            elsif input['filters'].size == 1
              input['filters']&.map do |filter|
                { filter['operator'] => { 'field' => filter['field'],
                                          'value' => filter['value']&.split(',') } }
              end&.first
            end
          end
        orderby = if input['ordering'].present?
                    { 'order' => { 'field' => input['ordering']['sort_field'],
                                   input['ordering']['sort_order'] => '' } }
                  end
        function = {
          '@controlid' => 'testControlId',
          'query' => {
            'object' => 'PODOCUMENT',
            'select' => select_fields,
            'filter' => query,
            'orderby' => orderby,
            'options' => input['options'],
            'pagesize' => input['pagesize'] || 100,
            'offset' => input['offset'] || 0
          }.compact
        }
        response_data = call('get_api_response_data_element', function)

        {
          po_documents: call('format_response',
                             call('parse_xml_to_hash',
                                  'xml' => response_data,
                                  'array_fields' => ['PODOCUMENT'])&.
                             []('PODOCUMENT')) || []
        }
      end,

      input_fields: ->(object_definitions) { object_definitions['po_document_search'] },

      output_fields: lambda do |object_definitions|
        [{
          name: 'po_documents',
          label: 'Purchasing transactions',
          type: 'array',
          of: 'object',
          properties: object_definitions['po_document']
        }]
      end,

      sample_output: lambda do |_connection, _input|
        field_function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'PODOCUMENT' }
        }
        get_fields_response = call('get_api_response_data_element', field_function)
        fields =
          call('parse_xml_to_hash',
               'xml' => get_fields_response,
               'array_fields' => ['Field'])&.
          dig('Type', 'Fields', 'Field')&.pluck('Name')&.
          reject { |name| %w[ENABLEDOCCHANGE].include?(name) }
        function = {
          '@controlid' => 'testControlId',
          'query' => {
            'object' => 'PODOCUMENT',
            'select' => { 'field' => fields },
            'pagesize' => 1
          }.compact
        }
        response_data = call('get_api_response_data_element', function)

        {
          po_documents: call('format_response',
                             call('parse_xml_to_hash',
                                  'xml' => response_data,
                                  'array_fields' => ['PODOCUMENT'])&.
                             []('PODOCUMENT')) || []
        }
      end
    },

    # Account
    search_accounts_query: {
      title: 'Search accounts',
      description: "Search <span class='provider'>Accounts</span> in " \
      "<span class='provider'>Sage Intacct (Custom)</span>",
      help: 'Search will return results that match all your search criteria. ' \
      'Returns a maximum of 2000 records.',

      execute: lambda do |_connection, input|
        field_function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'GLACCOUNT' }
        }
        get_fields_response = call('get_api_response_data_element', field_function)
        fields =
          call('parse_xml_to_hash',
               'xml' => get_fields_response,
               'array_fields' => ['Field'])&.
          dig('Type', 'Fields', 'Field')&.pluck('Name')
        select_fields =  { 'field' => input['fields']&.split(',') || fields }
        filter_condition = input['filter_condition'] || 'and'
        query =
          if input['filters'].present?
            if input['filters'].size > 1
              {
                filter_condition =>
                  input['filters']&.map do |filter|
                    { filter['operator'] => { 'field' => filter['field'],
                                              'value' => filter['value']&.split(',') } }
                  end&.each_with_object({}) do |hash, object|
                    hash.each { |key, value| (object[key] ||= []) << value }
                  end
              }
            elsif input['filters'].size == 1
              input['filters']&.map do |filter|
                { filter['operator'] => { 'field' => filter['field'],
                                          'value' => filter['value']&.split(',') } }
              end&.first
            end
          end
        orderby = if input['ordering'].present?
                    { 'order' => { 'field' => input['ordering']['sort_field'],
                                   input['ordering']['sort_order'] => '' } }
                  end
        function = {
          '@controlid' => 'testControlId',
          'query' => {
            'object' => 'GLACCOUNT',
            'select' => select_fields,
            'filter' => query,
            'orderby' => orderby,
            'options' => input['options'],
            'pagesize' => input['pagesize'] || 100,
            'offset' => input['offset'] || 0
          }.compact
        }
        response_data = call('get_api_response_data_element', function)

        {
          accounts: call('format_response',
                         call('parse_xml_to_hash',
                              'xml' => response_data,
                              'array_fields' => ['GLACCOUNT'])&.
                         []('GLACCOUNT')) || []
        }
      end,

      input_fields: ->(object_definitions) { object_definitions['account_search'] },

      output_fields: lambda do |object_definitions|
        [{
          name: 'accounts',
          type: 'array',
          of: 'object',
          properties: object_definitions['account']
        }]
      end,

      sample_output: lambda do |_connection, _input|
        field_function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'GLACCOUNT' }
        }
        get_fields_response = call('get_api_response_data_element', field_function)
        fields =
          call('parse_xml_to_hash',
               'xml' => get_fields_response,
               'array_fields' => ['Field'])&.
          dig('Type', 'Fields', 'Field')&.pluck('Name')
        function = {
          '@controlid' => 'testControlId',
          'query' => {
            'object' => 'GLACCOUNT',
            'select' => { 'field' => fields },
            'pagesize' => 1
          }.compact
        }
        response_data = call('get_api_response_data_element', function)

        {
          accounts: call('format_response',
                         call('parse_xml_to_hash',
                              'xml' => response_data,
                              'array_fields' => ['GLACCOUNT'])&.
                         []('GLACCOUNT')) || []
        }
      end
    },

    # Location
    search_locations_query: {
      title: 'Search locations',
      description: "Search <span class='provider'>Locations</span> in " \
      "<span class='provider'>Sage Intacct (Custom)</span>",
      help: 'Search will return results that match all your search criteria. ' \
      'Returns a maximum of 2000 records.',

      execute: lambda do |_connection, input|
        field_function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'LOCATION' }
        }
        get_fields_response = call('get_api_response_data_element', field_function)
        fields =
          call('parse_xml_to_hash',
               'xml' => get_fields_response,
               'array_fields' => ['Field'])&.
          dig('Type', 'Fields', 'Field')&.pluck('Name')
        select_fields =  { 'field' => input['fields']&.split(',') || fields }
        filter_condition = input['filter_condition'] || 'and'
        query =
          if input['filters'].present?
            if input['filters'].size > 1
              {
                filter_condition =>
                  input['filters']&.map do |filter|
                    { filter['operator'] => { 'field' => filter['field'],
                                              'value' => filter['value']&.split(',') } }
                  end&.each_with_object({}) do |hash, object|
                    hash.each { |key, value| (object[key] ||= []) << value }
                  end
              }
            elsif input['filters'].size == 1
              input['filters']&.map do |filter|
                { filter['operator'] => { 'field' => filter['field'],
                                          'value' => filter['value']&.split(',') } }
              end&.first
            end
          end
        orderby = if input['ordering'].present?
                    { 'order' => { 'field' => input['ordering']['sort_field'],
                                   input['ordering']['sort_order'] => '' } }
                  end
        function = {
          '@controlid' => 'testControlId',
          'query' => {
            'object' => 'LOCATION',
            'select' => select_fields,
            'filter' => query,
            'orderby' => orderby,
            'options' => input['options'],
            'pagesize' => input['pagesize'] || 100,
            'offset' => input['offset'] || 0
          }.compact
        }
        response_data = call('get_api_response_data_element', function)

        {
          locations: call('format_response',
                          call('parse_xml_to_hash',
                               'xml' => response_data,
                               'array_fields' => ['LOCATION'])&.
                          []('LOCATION')) || []
        }
      end,

      input_fields: ->(object_definitions) { object_definitions['location_search'] },

      output_fields: lambda do |object_definitions|
        [{
          name: 'locations',
          type: 'array',
          of: 'object',
          properties: object_definitions['location']
        }]
      end,

      sample_output: lambda do |_connection, _input|
        field_function = {
          '@controlid' => 'testControlId',
          'inspect' => { '@detail' => '1', 'object' => 'LOCATION' }
        }
        get_fields_response = call('get_api_response_data_element', field_function)
        fields =
          call('parse_xml_to_hash',
               'xml' => get_fields_response,
               'array_fields' => ['Field'])&.
          dig('Type', 'Fields', 'Field')&.pluck('Name')
        function = {
          '@controlid' => 'testControlId',
          'query' => {
            'object' => 'LOCATION',
            'select' => { 'field' => fields },
            'pagesize' => 1
          }.compact
        }
        response_data = call('get_api_response_data_element', function)

        {
          locations: call('format_response',
                          call('parse_xml_to_hash',
                               'xml' => response_data,
                               'array_fields' => ['LOCATION'])&.
                          []('LOCATION')) || []
        }
      end
    }
  },

  triggers: {
    new_contract: {
      description: "New <span class='provider'>contract</span> in "\
      "<span class='provider'>Sage Intacct (Custom)</span>",
      help: '<b>Make sure you have subscribed for Contract ' \
      'module in your Sage Intacct instance.</b>',

      input_fields: lambda do |_object_definitions|
        [{
          name: 'since',
          label: 'When first started, this recipe should pick up events from',
          hint: 'When you start recipe for the first time, ' \
            'it picks up trigger events from this specified date and time. ' \
            'Leave empty to get records created or updated one hour ago',
          sticky: true,
          type: 'timestamp'
        }]
      end,

      poll: lambda do |_connection, input, closure|
        page_size = 50
        created_since = (closure&.[]('created_since') || input['since'] ||
                          1.hour.ago)
        result_id = closure&.[]('result_id')
        function =
          if result_id.present?
            {
              '@controlid' => 'testControlId',
              'readMore' => { 'resultId' => result_id }
            }
          else
            query = 'WHENCREATED >= ' \
            "'#{created_since&.to_time&.utc&.strftime('%m/%d/%Y %H:%M:%S')}' " \
            "and WHENCREATED < #{now&.utc&.strftime('%m/%d/%Y %H:%M:%S')}"

            {
              '@controlid' => 'testControlId',
              'readByQuery' => {
                'object' => 'CONTRACT',
                'fields' => '*',
                'query' => query,
                'pagesize' => page_size
              }
            }
          end
        response_result = call('get_api_response_result_element', function)
        contract_data = call('format_response',
                             call('parse_xml_to_hash',
                                  'xml' => response_result,
                                  'array_fields' => ['contract'])&.
                               []('data'))
        more_pages = (result_id = contract_data['__resultId'].presence) || false
        closure = if more_pages
                    {
                      'result_id' => result_id,
                      'created_since' => created_since
                    }
                  else
                    { 'result_id' => nil, 'created_since' => now }
                  end

        {
          events: contract_data&.[]('contract'),
          next_poll: closure,
          can_poll_more: more_pages
        }
      end,

      dedup: lambda do |contract|
        "#{contract['RECORDNO']}@#{contract['WHENCREATED']}"
      end,

      output_fields: ->(object_definitions) { object_definitions['contract'] },

      sample_output: lambda do |_connection, _input|
        function = {
          '@controlid' => 'testControlId',
          'readByQuery' => {
            'object' => 'CONTRACT',
            'fields' => '*',
            'query' => '',
            'pagesize' => '1'
          }
        }
        response_data = call('get_api_response_data_element', function)

        call('format_response',
             call('parse_xml_to_hash',
                  'xml' => response_data,
                  'array_fields' => ['contract'])&.
               dig('contract', 0)) || {}
      end
    },

    new_updated_contract: {
      title: 'New/updated contract',
      description: "New or updated <span class='provider'>contract</span> in "\
      "<span class='provider'>Sage Intacct (Custom)</span>",
      help: '<b>Make sure you have subscribed for Contract ' \
      'module in your Sage Intacct instance.</b>',

      input_fields: lambda do |_object_definitions|
        [{
          name: 'since',
          label: 'When first started, this recipe should pick up events from',
          hint: 'When you start recipe for the first time, ' \
            'it picks up trigger events from this specified date and time. ' \
            'Leave empty to get records created or updated one hour ago',
          sticky: true,
          type: 'timestamp'
        }]
      end,

      poll: lambda do |_connection, input, closure|
        page_size = 50
        updated_since = (closure&.[]('updated_since') || input['since'] ||
                          1.hour.ago)
        result_id = closure&.[]('result_id')
        function =
          if result_id.present?
            {
              '@controlid' => 'testControlId',
              'readMore' => { 'resultId' => result_id }
            }
          else
            query = 'WHENMODIFIED >= ' \
            "'#{updated_since&.to_time&.utc&.strftime('%m/%d/%Y %H:%M:%S')}' " \
            "and WHENMODIFIED < #{now&.utc&.strftime('%m/%d/%Y %H:%M:%S')}"
            {
              '@controlid' => 'testControlId',
              'readByQuery' => {
                'object' => 'CONTRACT',
                'fields' => '*',
                'query' => query,
                'pagesize' => page_size
              }
            }
          end
        response_result = call('get_api_response_result_element', function)
        contract_data = call('format_response',
                             call('parse_xml_to_hash',
                                  'xml' => response_result,
                                  'array_fields' => ['contract'])&.
                               []('data'))
        more_pages = (result_id = contract_data['__resultId'].presence) || false
        closure = if more_pages
                    {
                      'result_id' => result_id,
                      'updated_since' => updated_since
                    }
                  else
                    { 'result_id' => nil, 'updated_since' => now }
                  end

        {
          events: contract_data&.[]('contract'),
          next_poll: closure,
          can_poll_more: more_pages
        }
      end,

      dedup: lambda do |contract|
        "#{contract['RECORDNO']}@#{contract['WHENMODIFIED']}"
      end,

      output_fields: ->(object_definitions) { object_definitions['contract'] },

      sample_output: lambda do |_connection, _input|
        function = {
          '@controlid' => 'testControlId',
          'readByQuery' => {
            'object' => 'CONTRACT',
            'fields' => '*',
            'query' => '',
            'pagesize' => '1'
          }
        }
        response_data = call('get_api_response_data_element', function)

        call('format_response',
             call('parse_xml_to_hash',
                  'xml' => response_data,
                  'array_fields' => ['contract'])&.
               dig('contract', 0)) || {}
      end
    },

    new_updated_invoice: {
      title: 'New/updated invoice',
      description: "New or updated <span class='provider'>invoice</span> in "\
      "<span class='provider'>Sage Intacct (Custom)</span>",

      input_fields: lambda do |_object_definitions|
        [{
          name: 'since',
          label: 'When first started, this recipe should pick up events from',
          hint: 'When you start recipe for the first time, ' \
            'it picks up trigger events from this specified date and time. ' \
            'Leave empty to get records created or updated one hour ago',
          sticky: true,
          type: 'timestamp'
        }]
      end,

      poll: lambda do |_connection, input, closure|
        page_size = 50
        updated_since = (closure&.[]('updated_since') || input['since'] ||
                          1.hour.ago)
        result_id = closure&.[]('result_id')
        function =
          if result_id.present?
            {
              '@controlid' => 'testControlId',
              'readMore' => { 'resultId' => result_id }
            }
          else
            query = 'WHENMODIFIED >= ' \
            "'#{updated_since&.to_time&.utc&.strftime('%m/%d/%Y %H:%M:%S')}' " \
            "and WHENMODIFIED < #{now&.utc&.strftime('%m/%d/%Y %H:%M:%S')}"
            {
              '@controlid' => 'testControlId',
              'readByQuery' => {
                'object' => 'ARINVOICE',
                'fields' => '*',
                'query' => query,
                'pagesize' => page_size
              }
            }
          end
        response_result = call('get_api_response_result_element', function)
        invoice_data = call('format_response',
                            call('parse_xml_to_hash',
                                 'xml' => response_result,
                                 'array_fields' => ['arinvoice'])&.
                              []('data'))
        more_pages = (result_id = invoice_data['__resultId'].presence) || false
        closure = if more_pages
                    {
                      'result_id' => result_id,
                      'updated_since' => updated_since
                    }
                  else
                    { 'result_id' => nil, 'updated_since' => now }
                  end

        {
          events: invoice_data&.[]('arinvoice'),
          next_poll: closure,
          can_poll_more: more_pages
        }
      end,

      dedup: lambda do |invoice|
        "#{invoice['RECORDNO']}@#{invoice['WHENMODIFIED']}"
      end,

      output_fields: ->(object_definitions) { object_definitions['invoice'] },

      sample_output: lambda do |_connection, _input|
        function = {
          '@controlid' => 'testControlId',
          'readByQuery' => {
            'object' => 'ARINVOICE',
            'fields' => '*',
            'query' => '',
            'pagesize' => '1'
          }
        }
        response_data = call('get_api_response_data_element', function)

        call('format_response',
             call('parse_xml_to_hash',
                  'xml' => response_data,
                  'array_fields' => ['arinvoice'])&.
                          dig('arinvoice', 0)) || {}
      end
    }
  },

  pick_lists: {
    adjustment_process_types: lambda do |_connection|
      [%w[One\ time One\ time], %w[Distributed Distributed]]
    end,

    adv_bill_by_types: ->(_connection) { [%w[Days days], %w[Months months]] },

    billing_frequencies: lambda do |_connection|
      %w[Monthly Quarterly Annually].map { |val| [val, val] }
    end,

    billing_methods: lambda do |_connection|
      ['Fixed price', 'Quantity based'].map { |val| [val, val] }
    end,

    billing_options: lambda do |_connection|
      ['One-time', 'Use billing template', 'Include with every invoice'].
        map { |val| [val, val] }
    end,

    classes: lambda do |_connection|
      function = {
        '@controlid' => 'testControlId',
        'readByQuery' => {
          'object' => 'CLASS',
          'fields' => 'NAME, CLASSID',
          'query' => "STATUS = 'T'",
          'pagesize' => '1000'
        }
      }
      response_data = call('get_api_response_data_element', function)

      call('parse_xml_to_hash',
           'xml' => response_data,
           'array_fields' => ['class'])&.
        []('class')&.
        pluck('NAME', 'CLASSID') || []
    end,

    contact_names: lambda do |_connection|
      function = {
        '@controlid' => 'testControlId',
        'readByQuery' => {
          'object' => 'CONTACT',
          'fields' => 'RECORDNO, CONTACTNAME',
          'query' => "STATUS = 'T'",
          'pagesize' => '1000'
        }
      }
      response_data = call('get_api_response_data_element', function)

      call('parse_xml_to_hash',
           'xml' => response_data,
           'array_fields' => ['contact'])&.
        []('contact')&.
        pluck('CONTACTNAME', 'CONTACTNAME') || []
    end,

    contract_states: lambda do |_connection|
      ['Draft', 'In progress'].map { |val| [val, val] }
    end,

    customers: lambda do |_connection|
      function = {
        '@controlid' => 'testControlId',
        'readByQuery' => {
          'object' => 'CUSTOMER',
          'fields' => 'NAME, CUSTOMERID',
          'query' => "STATUS = 'T'",
          'pagesize' => '1000'
        }
      }
      response_data = call('get_api_response_data_element', function)

      call('parse_xml_to_hash',
           'xml' => response_data,
           'array_fields' => ['customer'])&.
        []('customer')&.
        pluck('NAME', 'CUSTOMERID') || []
    end,

    departments: lambda do |_connection|
      function = {
        '@controlid' => 'testControlId',
        'readByQuery' => {
          'object' => 'DEPARTMENT',
          'fields' => 'TITLE, DEPARTMENTID',
          'query' => "STATUS = 'T'",
          'pagesize' => '1000'
        }
      }
      response_data = call('get_api_response_data_element', function)

      call('parse_xml_to_hash',
           'xml' => response_data,
           'array_fields' => ['department'])&.
        []('department')&.
        pluck('TITLE', 'DEPARTMENTID') || []
    end,

    document_types: lambda do |_connection, object:|
      function = {
        '@controlid' => 'testControlId',
        'readByQuery' => {
          'object' => (object = "#{object}PARAMS"),
          'fields' => 'DESCRIPTION, DOCID',
          'query' => '',
          'pagesize' => '1000'
        }
      }
      response_data = call('get_api_response_data_element', function)

      call('parse_xml_to_hash',
           'xml' => response_data,
           'array_fields' => [object.downcase])&.
        [](object.downcase)&.
        pluck('DESCRIPTION', 'DOCID') || []
    end,

    employees: lambda do |_connection|
      function = {
        '@controlid' => 'testControlId',
        'readByQuery' => {
          'object' => 'EMPLOYEE',
          'fields' => 'CONTACT_NAME, EMPLOYEEID',
          'query' => "STATUS = 'T'",
          'pagesize' => '1000'
        }
      }
      response_data = call('get_api_response_data_element', function)

      call('parse_xml_to_hash',
           'xml' => response_data,
           'array_fields' => ['employee'])&.
        []('employee')&.
        pluck('CONTACT_NAME', 'EMPLOYEEID') || []
    end,

    feed_types: lambda do |_connection|
      [['XML format', 'xml'], ['Online bank feeds', 'onl']]
    end,

    genders: ->(_connection) { [%w[Male male], %w[Female female]] },

    invoice_actions: lambda do |_connection|
      %w[Draft Submit].map { |val| [val, val] }
    end,

    items: lambda do |_connection|
      function = {
        '@controlid' => 'testControlId',
        'readByQuery' => {
          'object' => 'ITEM',
          'fields' => 'NAME, ITEMID',
          'query' => "STATUS = 'T'",
          'pagesize' => '1000'
        }
      }
      response_data = call('get_api_response_data_element', function)

      call('parse_xml_to_hash',
           'xml' => response_data,
           'array_fields' => ['item'])&.
        []('item')&.
        pluck('NAME', 'ITEMID') || []
    end,

    locations: lambda do |_connection|
      function = {
        '@controlid' => 'testControlId',
        'readByQuery' => {
          'object' => 'LOCATION',
          'fields' => 'NAME, LOCATIONID',
          'query' => "STATUS = 'T'",
          'pagesize' => '1000'
        }
      }
      response_data = call('get_api_response_data_element', function)

      call('parse_xml_to_hash',
           'xml' => response_data,
           'array_fields' => ['location'])&.
        []('location')&.
        pluck('NAME', 'LOCATIONID') || []
    end,

    methods: lambda do |_connection|
      %w[Volume Weight Count].map { |val| [val, val] }
    end,

    projects: lambda do |_connection|
      function = {
        '@controlid' => 'testControlId',
        'readByQuery' => {
          'object' => 'PROJECT',
          'fields' => 'NAME, PROJECTID',
          'query' => "STATUS = 'T'",
          'pagesize' => '1000'
        }
      }
      response_data = call('get_api_response_data_element', function)

      call('parse_xml_to_hash',
           'xml' => response_data,
           'array_fields' => ['project'])&.
        []('project')&.
        pluck('NAME', 'PROJECTID') || []
    end,

    renewal_term_periods: lambda do |_connection|
      %w[Years Months Days].map { |val| [val, val] }
    end,

    revpostings: lambda do |_connection|
      ['Component Level', 'Kit Level'].map { |val| [val, val] }
    end,

    revprintings: lambda do |_connection|
      ['Individual Components', 'Kit'].map { |val| [val, val] }
    end,

    so_po_objects: lambda do |_connection|
      [
        ['Sale order', 'SODOCUMENT'],
        ['Purchase order', 'PODOCUMENT']
        # TODO: check this
        # ['Sale order detail', 'SODOCUMENTENTRY'],
        # ['Purchase order detail', 'PODOCUMENTENTRY']
      ]
    end,

    standard_objects: lambda do |_connection|
      [
        ['AP Adjustment', 'APADJUSTMENT'],
        ['AP Adjustment Detail', 'APADJUSTMENTITEM'],
        ['AP Bill', 'APBILL'],
        ['AP Bill Detail', 'APBILLITEM'],
        ['AP Bill Payment', 'APBILLPAYMENT'],
        ['AP Payment', 'APPAYMENT'],
        ['AP Payment Detail', 'APPAYMENTITEM'],
        ['AR Adjustment', 'ARADJUSTMENT'],
        ['AR Adjustment Detail', 'ARADJUSTMENTITEM'],
        ['AR Invoice', 'ARINVOICE'],
        ['AR Invoice Detail', 'ARINVOICEITEM'],
        ['AR Invoice Payment', 'ARINVOICEPAYMENT'],
        ['AR Payment', 'ARPAYMENT'],
        ['AR Payment Detail', 'ARPAYMENTITEM'],
        %w[Class CLASS],
        ['Consolidation Account', 'CNSACCOUNT'],
        ['Consolidation Account Balance', 'CNSACCTBAL'],
        ['Consolidation Period', 'CNSPERIOD'],
        ['Company Information', 'COMPANY'],
        ['Company Preference', 'COMPANYPREF'],
        %w[Customer CUSTOMER],
        %w[Department DEPARTMENT],
        ['Employee Expense', 'EEXPENSES'],
        ['Employee Expense Detail', 'EEXPENSESITEM'],
        ['Employee Expenses Payment', 'EEXPENSESPAYMENT'],
        %w[Employee EMPLOYEE],
        ['Employee Expense Reimbursement', 'EPPAYMENT'],
        ['Employee Payment Detail', 'EPPAYMENTITEM'],
        ['Exchange Rate', 'EXCHANGERATE'],
        ['Exchange Rate Entry', 'EXCHANGERATEENTRY'],
        ['GL Account', 'GLACCOUNT'],
        ['GL Batch', 'GLBATCH'],
        ['GL Entry', 'GLENTRY'],
        ['Inventory Document', 'INVDOCUMENT'],
        ['Inventory Document Detail', 'INVDOCUMENTENTRY'],
        %w[Item ITEM],
        %w[Location LOCATION],
        ['Purchasing Document', 'PODOCUMENT'],
        ['Purchasing Approval History', 'PODOCUMENTAPPROVAL'],
        ['Purchasing Document Detail', 'PODOCUMENTENTRY'],
        %w[Project PROJECT],
        ['Renewal Template', 'RENEWALMACRO'],
        ['Revenue Recognition Schedule', 'REVRECSCHEDULE'],
        ['Revenue Recognition Schedule Entry', 'REVRECSCHEDULEENTRY'],
        ['Sales document', 'SODOCUMENT'],
        ['Sales Document Detail', 'SODOCUMENTENTRY'],
        %w[Subsidiary SUBSIDIARY],
        ['Currency And Format Setup', 'TRXCURRENCIES'],
        %w[User USERINFO],
        %w[Vendor VENDOR],
        %w[Warehouse WAREHOUSE],
        ['Wells Fargo Payment Manager Summary', 'WFPMBATCH'],
        ['Wells Fargo Payment Request', 'WFPMPAYMENTREQUEST'],
        ['Vendor Type', 'VENDTYPE'],
        %w[Task TASK],
        %w[Timesheet TIMESHEET],
        ['Timesheet Entry', 'TIMESHEETENTRY'],
        ['AP Term', 'APTERM'],
        ['AR Term', 'ARTERM'],
        ['AR Payment Summary', 'ARPAYMENTBATCH'],
        ['GL Journal', 'GLJOURNAL'],
        %w[Allocation ALLOCATION],
        ['AP Bill Summary', 'APBILLBATCH'],
        ['AR Invoice Summary', 'ARINVOICEBATCH'],
        ['AR Account Label', 'ARACCOUNTLABEL'],
        ['AP Account Label', 'APACCOUNTLABEL'],
        %w[Contact CONTACT],
        %w[Creditcard CREDITCARD],
        ['Checking Account', 'CHECKINGACCOUNT'],
        ['Bank Account', 'SAVINGSACCOUNT'],
        ['Bank Account', 'BANKACCOUNT'],
        ['Statistical Journal', 'STATJOURNAL'],
        ['AP Payment Request', 'APPAYMENTREQUEST'],
        ['AP Recurring Bill', 'APRECURBILL'],
        ['Billable Expense', 'BILLABLEEXPENSES'],
        ['Check Layout', 'CHECKLAYOUT'],
        ['Recurring document entry', 'RECURDOCUMENTENTRY'],
        ['Pending Reimbursement', 'EPPAYMENTREQUEST'],
        ['Exchange Rate Type', 'EXCHANGERATETYPES'],
        ['Expense Approval', 'EXPENSESAPPROVAL'],
        ['Financial Account', 'FINANCIALACCOUNT'],
        ['GAAP Adjustment Journal', 'GAAPADJJRNL'],
        ['General Ledger Detail', 'GLDETAIL'],
        ['Inter Entity Relationship', 'IERELATION'],
        ['Invoice Run', 'INVOICERUN'],
        ['Recurring Inventory Transaction', 'INVRECURDOCUMENT'],
        %w[Entity LOCATIONENTITY],
        ['Recurring Purchasing Transaction', 'PORECURDOCUMENT'],
        ['Project Resource', 'PROJECTRESOURCES'],
        ['Project Status', 'PROJECTSTATUS'],
        ['Project Type', 'PROJECTTYPE'],
        ['Recurring Journal Entry', 'RECURGLBATCH'],
        ['Recurring Journal Entry Details', 'RECURGLENTRY'],
        ['Revenue Recognition Change History', 'REVRECCHANGELOG'],
        ['Recurring Order Entry Transaction', 'SORECURDOCUMENT'],
        ['Build/Disassemble Kits Transaction', 'STKITDOCUMENT'],
        ['Build/Disassemble Kits Transaction Detail', 'STKITDOCUMENTENTRY'],
        ['Task Resource', 'TASKRESOURCES'],
        ['Tax Adjustment Journal', 'TAXADJJRNL'],
        ['Timesheet Approval History', 'TIMESHEETAPPROVAL'],
        ['Time Type', 'TIMETYPE'],
        %w[Budget BUDGETHEADER],
        ['GL Budget', 'GLBUDGET'],
        ['Reporting Period', 'REPORTINGPERIOD'],
        ['Statistical Account', 'STATACCOUNT'],
        ['Account Title By Entity', 'ACCTTITLEBYLOC'],
        ['Revenue Recognition Template', 'REVRECTEMPLATE'],
        ['Revenue Recognition Template Entry', 'REVRECTEMPLENTRY'],
        ['Revenue Recognition Template Entry', 'REVRECTEMPLMILESTONE'],
        ['Revenue Recognition Schedule Entry Task Detail',
         'REVRECSCHEDULEENTRYTASK'],
        ['Earning Type', 'EARNINGTYPE'],
        ['Employee Rate', 'EMPLOYEERATE'],
        ['User Permissions Activity', 'AUDUSERTRAIL'],
        ['Activity Trail', 'ACTIVITYLOG'],
        %w[Comment COMMENTS],
        ['GL Account Balance', 'GLACCOUNTBALANCE'],
        ['Billing Template', 'BILLINGTEMPLATE'],
        ['Billing Schedule', 'BILLINGSCHEDULE'],
        %w[Journal JOURNAL],
        ['Open book log', 'OPENBOOKS'],
        ['Close book log', 'CLOSEBOOKS'],
        ['Unit Of Measure', 'UOM'],
        ['Unit Of Measure Detail', 'UOMDETAIL'],
        ['Price List', 'INVPRICELIST'],
        ['Price List Entry', 'INVPRICELISTENTRY'],
        ['SO Price List', 'SOPRICELIST'],
        ['SO Price List Entry', 'SOPRICELISTENTRY'],
        ['PO Price List', 'POPRICELIST'],
        ['PO Price List Entry', 'POPRICELISTENTRY'],
        ['GL Account Group', 'GLACCTGRP'],
        ['GL Account Group Range', 'ACCTRANGE'],
        ['GL Account Group Member', 'GLACCTGRPMEMBER'],
        ['GL Computation Group Member', 'GLCOMPGRPMEMBER'],
        ['GL Account Category', 'GLCOACATMEMBER'],
        ['Allocation Entry', 'ALLOCATIONENTRY'],
        ['Employee Type', 'EMPLOYEETYPE'],
        ['Employee Entity Contact', 'EMPLOYEEENTITYCONTACTS'],
        ['GL Entry Resolve', 'GLRESOLVE'],
        ['ACH Bank', 'ACHBANK'],
        %w[Aisle AISLE],
        %w[Bin BIN],
        %w[Row ICROW],
        ['Product Line', 'PRODUCTLINE'],
        ['Item/Vendor Info', 'ITEMVENDOR'],
        ['Item/Warehouse Info', 'ITEMWAREHOUSEINFO'],
        ['Kit Components', 'ITEMCOMPONENT'],
        ['Account Groups Hierarchy', 'GLACCTGRPHIERARCHY'],
        ['Contact Tax Group', 'TAXGROUP'],
        ['Item Tax Group', 'ITEMTAXGROUP'],
        ['AR Account Label Tax Group', 'ACCTLABELTAXGROUP'],
        ['Location Group', 'LOCATIONGROUP'],
        ['Department Group', 'DEPARTMENTGROUP'],
        ['Vendor Group', 'VENDORGROUP'],
        ['Customer Group', 'CUSTOMERGROUP'],
        ['Project Group', 'PROJECTGROUP'],
        ['Employee Group', 'EMPLOYEEGROUP'],
        ['Class Group', 'CLASSGROUP'],
        ['Item Group', 'ITEMGROUP'],
        ['Expense Type', 'EEACCOUNTLABEL'],
        ['User Role', 'USERROLES'],
        ['Kit Costing', 'KITCOSTING'],
        ['Customer Visibility', 'CUSTOMERVISIBILITY'],
        ['Vendor Visibility', 'VENDORVISIBILITY'],
        ['Customer Type', 'CUSTTYPE'],
        ['Territory Group', 'TERRITORYGROUP'],
        ['Territory Group Member', 'TERRITORYGRPMEMBER'],
        ['General Ledger Document Detail', 'GLDOCDETAIL'],
        ['Positions and Skills', 'POSITIONSKILL'],
        ['Employee Positions and Skills', 'EMPLOYEEPOSITIONSKILL'],
        ['Out of Office', 'OUTOFOFFICE'],
        ['Employee out of Office', 'EMPLOYEEOUTOFOFFICE'],
        ['Project Totals', 'PROJECTTOTALS'],
        %w[Prtaxentry PRTAXENTRY],
        ['Line Items', 'TRANSTMPLENTRY'],
        ['Document Sub Totals', 'INVDOCUMENTSUBTOTALS'],
        ['Purchasing Document Subtotals', 'PODOCUMENTSUBTOTALS'],
        ['Order Entry Transaction Subtotals', 'SODOCUMENTSUBTOTALS'],
        ['INV Recurring Sub Totals', 'INVRECURSUBTOTALS'],
        ['PO Recurring Sub Totals', 'PORECURSUBTOTALS'],
        ['SO Recurring Sub Totals', 'SORECURSUBTOTALS'],
        ['Recurring AP Bill Detail', 'APRECURBILLENTRY'],
        ['Transaction Rule', 'TRANSACTIONRULE'],
        ['Transaction Rule Detail', 'TRANSACTIONRULEDETAIL'],
        ['Project Transaction Rule', 'PROJECTTRANSACTIONRULE'],
        ['Expense Payment Type', 'EXPENSEPAYMENTTYPE'],
        ['Purchasing Approval Rule', 'POAPPROVALRULE'],
        ['Purchasing Approval Rule Details', 'POAPPROVALRULEDETAIL'],
        ['Purchasing Approval Policy', 'POAPPROVALPOLICY'],
        ['Purchasing Approval Policy Details', 'POAPPROVALPOLICYDETAIL'],
        ['Approval Delegate', 'POAPPROVALDELEGATE'],
        ['Manage Delegates', 'POAPPROVALDELEGATEDETAIL'],
        ['Value approval rule set', 'POAPPROVALRULESET'],
        ['Order Entry Subtotal Template', 'SOSUBTOTALTEMPLATE'],
        ['SubTotal Template Detail', 'SOSUBTOTALTEMPLATEDETAIL'],
        ['Purchasing Subtotal Template', 'POSUBTOTALTEMPLATE'],
        ['SubTotal Template Detail', 'POSUBTOTALTEMPLATEDETAIL'],
        ['AP Approval Rule', 'APAPPROVALRULE'],
        ['AP Approval Policy', 'APAPPROVALPOLICY'],
        ['Value approval rule set', 'APAPPROVALRULESET'],
        ['Inter Entity Setup', 'INTERENTITYSETUP'],
        %w[Entityacctdefault ENTITYACCTDEFAULT],
        ['Inter Entity Relationship', 'ENTITYACCTOVERRIDE'],
        ['Recurring AR Invoice Detail', 'ARRECURINVOICEENTRY'],
        ['AP Advance', 'APADVANCE'],
        ['AP Advance Detail', 'APADVANCEITEM'],
        ['AR Advance', 'ARADVANCE'],
        ['AR Advance Detail', 'ARADVANCEITEM'],
        ['Recurring AR Invoice', 'ARRECURINVOICE'],
        ['Expense Adjustments', 'EXPENSEADJUSTMENTS'],
        ['Expense Adjustments Detail', 'EXPENSEADJUSTMENTSITEM'],
        ['Transaction Template', 'TRANSTMPLBATCH'],
        ['PR Entry', 'PRENTRY'],
        ['Credit Card Transaction', 'CCTRANSACTION'],
        ['Credit Card Transaction Entry', 'CCTRANSACTIONENTRY'],
        ['Other Receipts', 'OTHERRECEIPTS'],
        ['Other Receipts Entry', 'OTHERRECEIPTSENTRY'],
        ['Credit Card Charges and Other Fees', 'CREDITCARDFEE'],
        ['Credit Card Charges and Other Fees Entry', 'CREDITCARDFEEENTRY'],
        ['Bank Interest and Charges', 'BANKFEE'],
        ['Bank Interest and Charges Entry', 'BANKFEEENTRY'],
        ['Funds Transfer', 'FUNDSTRANSFER'],
        ['Funds Transfer Entry', 'FUNDSTRANSFERENTRY'],
        ['Charge Payoffs', 'CHARGEPAYOFF'],
        ['Charge Payoffs Details', 'CHARGEPAYOFFENTRY'],
        %w[Deposits DEPOSIT],
        ['Deposits Details', 'DEPOSITENTRY'],
        ['AR Record', 'ARRECORD'],
        ['AR Detail', 'ARDETAIL'],
        ['User-Defined Book', 'USERADJBOOK'],
        ['User-Defined Journal', 'USERADJJRNL'],
        ['Data Delivery Service Job', 'DDSJOB'],
        ['API Usage Detail', 'APIUSAGEDETAIL'],
        ['Reporting Accounts', 'REPORTINGACHEADER'],
        ['Reporting Accounts', 'REPORTINGAC'],
        ['Vendor Aging Report', 'VENDAGING'],
        ['Customer Aging Report', 'CUSTAGING'],
        ['Email Template', 'EMAILTEMPLATE'],
        ['AP Record', 'APRECORD'],
        ['AP Detail', 'APDETAIL'],
        ['CM Record', 'CMRECORD'],
        ['CM Detail', 'CMDETAIL'],
        ['EE Record', 'EERECORD'],
        ['EE Detail', 'EEDETAIL'],
        ['User Permissions', 'USERRIGHTS'],
        %w[Budget GLBUDGETHEADER],
        ['GL Budget', 'GLBUDGETITEM'],
        %w[Docrecalls DOCRECALLS],
        ['Inventory GL Definitions', 'DOCUMENTPARINVGL'],
        ['GL Definitions', 'DOCUMENTPARPRGL'],
        ['Document Params SubTotal', 'DOCUMENTPARSUBTOTAL'],
        ['Document Paramaters Total', 'INVDOCUMENTPARTOTALS'],
        ['Inventory Transaction Definition', 'INVDOCUMENTPARAMS'],
        ['Item GL Group', 'ITEMGLGROUP'],
        ['Purchase Transaction Definition', 'PODOCUMENTPARAMS'],
        %w[Partnerfieldmap PARTNERFIELDMAP],
        ['Role users', 'ROLEUSERS'],
        %w[Roles ROLES],
        ['SO Transaction Definition', 'SODOCUMENTPARAMS'],
        %w[Summarybyentity SUMMARYBYENTITY],
        ['Tax Detail', 'TAXDETAIL'],
        ['User Group', 'USERGROUP'],
        ['API Usage Summary', 'APIUSAGESUMMARY'],
        ['AP Payables Payment', 'APPYMT'],
        ['New AP Payment Line Detail', 'APPYMTENTRY'],
        %w[Contract CONTRACT],
        ['Contract Line', 'CONTRACTDETAIL'],
        ['Revenue Template', 'CONTRACTREVENUETEMPLATE'],
        ['Contract Billing Template', 'CONTRACTBILLINGTEMPLATE'],
        ['Contract Billing Template Entry', 'CONTRACTBILLINGTEMPLATEENTRY'],
        ['Contract Revenue Schedule 1', 'CONTRACTREVENUESCHEDULE'],
        ['Contract Revenue Schedule 2', 'CONTRACTREVENUE2SCHEDULE'],
        ['Contract Revenue Schedule Entry', 'CONTRACTREVENUESCHEDULEENTRY'],
        ['Contract Billing Schedule', 'CONTRACTBILLINGSCHEDULE'],
        ['Contract Billing Schedule Entry', 'CONTRACTBILLINGSCHEDULEENTRY'],
        ['Contract Posting Configuration - Revenue', 'CONTRACTREVENUEGLCONFIG'],
        ['Contract Posting Configuration - Expense', 'CONTRACTEXPENSEGLCONFIG'],
        ['Contract Expense Template', 'CONTRACTEXPENSETEMPLATE'],
        ['Contract Expense', 'CONTRACTEXPENSE'],
        ['Contract Expense Schedule 1', 'CONTRACTEXPENSESCHEDULE'],
        ['Contract Expense Schedule Entry', 'CONTRACTEXPENSESCHEDULEENTRY'],
        ['Contract Usage Data', 'CONTRACTUSAGE'],
        ['Contract Schedule Forecast', 'CONTRACTSCHFORECAST'],
        ['MEA Price List', 'CONTRACTMEAPRICELIST'],
        ['MEA Price List Entry', 'CONTRACTMEAITEMPRICELIST'],
        ['MEA Price List Entry Detail', 'CONTRACTMEAITEMPRICELISTENTRY'],
        ['Billing Price List', 'CONTRACTPRICELIST'],
        ['Billing Price List Entry', 'CONTRACTITEMPRICELIST'],
        ['Billing Price List Entry Detail', 'CONTRACTITEMPRICELISTENTRY'],
        ['Contract Usage Billing', 'CONTRACTUSAGEBILLING'],
        ['Customer Email Template', 'CUSTOMEREMAILTEMPLATE'],
        ['Contract Expense Schedule 2', 'CONTRACTEXPENSE2SCHEDULE'],
        ['Billing Price List Entry Detail Tier', 'CONTRACTITEMPRCLSTENTYTIER'],
        ['Contract Compliance Task Item', 'CONTRACTCOMPLIANCETASKITEM'],
        ['Contract Compliance Checklist', 'CONTRACTCOMPLIANCETASK'],
        %w[Note NOTE],
        ['Contract Compliance Note', 'CONTRACTCOMPLIANCENOTE'],
        ['Contract Subledger Links', 'CONTRACTRESOLVE'],
        ['Contract MEA Allocation Scheme', 'CONTRACTMEABUNDLE'],
        ['Contract MEA Bundle Entry', 'CONTRACTMEABUNDLEENTRY'],
        ['Warehouse Group', 'WAREHOUSEGROUP'],
        ['Contract Group', 'CONTRACTGROUP'],
        ['Drop Ship History', 'DROPSHIPHISTORY'],
        ['AP Payables Payment Details', 'APPYMTDETAIL'],
        ['Role groups', 'ROLEGROUPS'],
        ['Role Policy Assignment', 'ROLEPOLICYASSIGNMENT'],
        ['Member User Groups', 'MEMBERUSERGROUP'],
        ['Custom Role Policy Assignment', 'CUSTOMROLEPOLASSIGNMENT'],
        ['Role assignments', 'ROLEASSIGNMENT'],
        ['Contract MEA Allocation Details', 'CONTRACTALLOCATIONFORBUNDLE'],
        ['Contract MEA Allocation Details', 'CONTRACTALLOCATIONDETAIL'],
        ['Contract MRR links', 'CONTRACTMRRRESOLVE'],
        ['Custom Renewal Amounts', 'RENEWALPRICINGOVERRIDE'],
        ['Audit History', 'AUDITHISTORY'],
        ['Contract Negative Billing', 'CONTRACTNEGATIVEBILLING'],
        ['Contract Negative Billing Entry', 'CONTRACTNEGATIVEBILLINGENTRY'],
        ['Generate Invoices Preview Snapshot Run', 'GENINVOICEPREBILL'],
        ['Generate Invoices Preview Snapshot Invoice',
         'GENINVOICEPREBILLHEADER'],
        ['Generate Invoices Preview Snapshot Line', 'GENINVOICEPREBILLLINE'],
        ['Generate Invoices', 'GENINVOICEPREVIEW'],
        ['Generate Invoices Preview Header', 'GENINVOICEPREVIEWHEADER'],
        ['Generate Invoices Preview Line', 'GENINVOICEPREVIEWLINE'],
        ['Generate Invoices Run', 'GENINVOICERUN'],
        ['Generate Invoice Filter Set', 'GENINVOICEFILTERS'],
        ['Contract Revenue Template Entry', 'CONTRACTREVENUETEMPLATEENTRY'],
        ['Warehouse Transfer', 'ICTRANSFER'],
        ['Warehouse Transfer Items', 'ICTRANSFERITEM'],
        ['Document Entry Tracking Details', 'DOCUMENTENTRYTRACKDETAIL'],
        %w[Scitemglgroup SCITEMGLGROUP],
        %w[Scpurchasingdoc SCPURCHASINGDOC],
        ['Observed Percent Completed', 'OBSPCTCOMPLETED'],
        ['User Restriction', 'USERRESTRICTION'],
        ['Cost history', 'COSTHISTORY'],
        ['Maintain Inventory Valuation', 'INVHLTHRUN'],
        ['MEA Fair Value Category', 'MEACATEGORY'],
        ['Advanced Audit History', 'ADVAUDITHISTORY'],
        ['Offline job queue', 'JOBQUEUERECORD'],
        ['Bank reconciliation', 'BANKACCTRECON'],
        ['Landed cost history', 'LANDEDCOSTHISTORY'],
        ['Replenishment Report', 'REPLENISHMENT'],
        ['COGS Closed JE', 'COGSCLOSEDJE'],
        ['MGL Account Balance', 'MGLACCOUNTBALANCE'],
        ['GL Account Allocation', 'GLACCTALLOCATION'],
        ['GL Account Allocation Source', 'GLACCTALLOCATIONSOURCE'],
        ['GL Account Allocation Basis', 'GLACCTALLOCATIONBASIS'],
        ['GL Account Allocation Target', 'GLACCTALLOCATIONTARGET'],
        ['GL Account Allocation Reverse', 'GLACCTALLOCATIONREVERSE'],
        ['Allocation log', 'GLACCTALLOCATIONRUN'],
        ['Account Allocation Groups', 'GLACCTALLOCATIONGRP'],
        ['Account Allocation Group Member', 'GLACCTALLOCATIONGRPMEMBER'],
        %w[Glacctallocationsourceadjbooks GLACCTALLOCATIONSOURCEADJBOOKS],
        %w[Glacctallocationbasisadjbooks GLACCTALLOCATIONBASISADJBOOKS],
        ['Accounting Sequence', 'JOURNALSEQNUM'],
        ['Accounting Sequence Number Entry', 'JOURNALSEQNUMENTRY'],
        ['Cost Type', 'COSTTYPE'],
        ['Cost type Group', 'COSTTYPEGROUP'],
        ['Cost type Group Members', 'COSTTYPEGRPMEMBER'],
        ['CostType/Group', 'COSTTYPENGROUPPICK'],
        ['Cost Type', 'COSTTYPEPICK'],
        ['Standard cost type', 'STANDARDCOSTTYPE'],
        ['Accumulation Type', 'ACCUMULATIONTYPE'],
        ['Standard Task', 'STANDARDTASK'],
        ['Replenishment Forecast Table', 'REPLENISHFORECAST'],
        ['Bank account transaction feed', 'BANKACCTTXNFEED'],
        ['Bank account transaction feed records', 'BANKACCTTXNRECORD'],
        ['Task Group', 'TASKGROUP'],
        ['IGC Book', 'GCBOOK'],
        ['Global consolidation book entities', 'GCBOOKENTITY'],
        ['Global consolidatoion book elimination accounts',
         'GCBOOKELIMACCOUNT'],
        ['Global consolidation book rate types', 'GCBOOKACCTRATETYPE'],
        ['Global consolidation Adj book journals', 'GCBOOKADJJOURNAL'],
        ['Document Estimate Landed Cost Entry', 'PODOCUMENTLCESTENTRY'],
        ['Task Group Members', 'TASKGRPMEMBER'],
        ['Task/Group', 'TASKNGROUPPICK'],
        %w[Task TASKPICK],
        ['Production units', 'PRODUCTIONUNITS'],
        ['Project Estimate', 'PJESTIMATE'],
        ['Project Estimate Entry', 'PJESTIMATEENTRY'],
        ['Estimate Type', 'PJESTIMATETYPE'],
        ['Cost Change History', 'COSTCHANGEHISTORY'],
        %w[Recurglacctallocation RECURGLACCTALLOCATION],
        ['Contract Type', 'CONTRACTTYPE'],
        ['Replenishment Forecast Detail Table', 'REPLENISHFORECASTDETAIL'],
        ['AR Receivables Payment', 'ARPYMT'],
        ['AR Receivables Payment Details', 'ARPYMTDETAIL'],
        ['AR Receivables Payment Line Detail', 'ARPYMTENTRY'],
        ['Contract resolve additional data', 'CONTRACTRSLVADDLDATA'],
        ['Process Contract Schedules', 'CONTRACTACPRUN'],
        ['Account Group Purpose', 'GLACCTGRPPURPOSE'],
        ['Inventory Total Detail', 'INVENTORYTOTALDETAIL'],
        ['Bank reconciliation records', 'BANKACCTRECONRECORD'],
        ['Buy to order History', 'BUYTOORDERHISTORY'],
        ['AP Retainage release', 'APRETAINAGERELEASE'],
        ['AP Retainage release entry', 'APRETAINAGERELEASEENTRY'],
        ['AR Retainage release', 'ARRETAINAGERELEASE'],
        ['AR Retainage release entry', 'ARRETAINAGERELEASEENTRY'],
        ['AR Releaseable Retainage Record', 'ARRELEASEABLERECORD'],
        ['AP Releaseable Retainage Record', 'APRELEASEABLERECORD'],
        ['Contract Schedules Processing Results Entry', 'CONTRACTACPRUNENTRY'],
        %w[Zone ZONE],
        ['Bin size', 'BINSIZE'],
        ['Bin face', 'BINFACE'],
        ['Report Type', 'GLREPORTTYPE'],
        ['Report Audience', 'GLREPORTAUDIENCE']
        # ['Adjustment Decrease', 'INVDOCUMENT'],
        # ['Adjustment Decrease Value', 'INVDOCUMENT'],
        # ['Adjustment Increase', 'INVDOCUMENT'],
        # ['Adjustment Increase Value', 'INVDOCUMENT'],
        # ['Beginning Balance', 'INVDOCUMENT'],
        # ['Inventory Damaged Goods', 'INVDOCUMENT'],
        # ['Inventory Receipt', 'INVDOCUMENT'],
        # ['Inventory Scrap or Spoilage', 'INVDOCUMENT'],
        # ['Inventory Shipper', 'INVDOCUMENT'],
        # ['Inventory Transfer In', 'INVDOCUMENT'],
        # ['Inventory Transfer Out', 'INVDOCUMENT'],
        # ['Adjustment Decrease Detail', 'INVDOCUMENTENTRY'],
        # ['Adjustment Decrease Value Detail', 'INVDOCUMENTENTRY'],
        # ['Adjustment Increase Detail', 'INVDOCUMENTENTRY'],
        # ['Adjustment Increase Value Detail', 'INVDOCUMENTENTRY'],
        # ['Beginning Balance Detail', 'INVDOCUMENTENTRY'],
        # ['Inventory Damaged Goods Detail', 'INVDOCUMENTENTRY'],
        # ['Inventory Receipt Detail', 'INVDOCUMENTENTRY'],
        # ['Inventory Scrap or Spoilage Detail', 'INVDOCUMENTENTRY'],
        # ['Inventory Shipper Detail', 'INVDOCUMENTENTRY'],
        # ['Inventory Transfer In Detail', 'INVDOCUMENTENTRY'],
        # ['Inventory Transfer Out Detail', 'INVDOCUMENTENTRY'],
        # ['Credit Memo', 'SODOCUMENT'],
        # %w[Invoice SODOCUMENT],
        # ['Invoice TM', 'SODOCUMENT'],
        # ['Renewal Invoice', 'SODOCUMENT'],
        # ['Renewal Order', 'SODOCUMENT'],
        # ['Sales Invoice', 'SODOCUMENT'],
        # ['Sales Invoice TM', 'SODOCUMENT'],
        # ['Sales Order', 'SODOCUMENT'],
        # ['Credit Memo Detail', 'SODOCUMENTENTRY'],
        # ['Invoice Detail', 'SODOCUMENTENTRY'],
        # ['Invoice TM Detail', 'SODOCUMENTENTRY'],
        # ['Renewal Invoice Detail', 'SODOCUMENTENTRY'],
        # ['Renewal Order Detail', 'SODOCUMENTENTRY'],
        # ['Sales Invoice Detail', 'SODOCUMENTENTRY'],
        # ['Sales Invoice TM Detail', 'SODOCUMENTENTRY'],
        # ['Sales Order Detail', 'SODOCUMENTENTRY'],
        # ['DP - Purchase Order', 'PODOCUMENT'],
        # ['Draft Invoice', 'PODOCUMENT'],
        # %w[Fulfillment PODOCUMENT],
        # ['Purchase Order', 'PODOCUMENT'],
        # ['Purchase Requisition', 'PODOCUMENT'],
        # ['Purchasing Debit Memo', 'PODOCUMENT'],
        # %w[Return PODOCUMENT],
        # ['Vendor Invoice', 'PODOCUMENT'],
        # ['DP - Purchase Order Detail', 'PODOCUMENTENTRY'],
        # ['Draft Invoice Detail', 'PODOCUMENTENTRY'],
        # ['Fulfillment Detail', 'PODOCUMENTENTRY'],
        # ['Purchase Order Detail', 'PODOCUMENTENTRY'],
        # ['Purchase Requisition Detail', 'PODOCUMENTENTRY'],
        # ['Purchasing Debit Memo Detail', 'PODOCUMENTENTRY'],
        # ['Return Detail', 'PODOCUMENTENTRY'],
        # ['Vendor Invoice Detail', 'PODOCUMENTENTRY'],
        # ['Credit Memo', 'SORECURDOCUMENT'],
        # %w[Invoice SORECURDOCUMENT],
        # ['Invoice TM', 'SORECURDOCUMENT'],
        # ['Renewal Invoice', 'SORECURDOCUMENT'],
        # ['Renewal Order', 'SORECURDOCUMENT'],
        # ['Sales Invoice', 'SORECURDOCUMENT'],
        # ['Sales Invoice TM', 'SORECURDOCUMENT'],
        # ['Sales Order', 'SORECURDOCUMENT']
      ]
    end,

    statuses: ->(_connection) { [%w[Active active], %w[Inactive inactive]] },

    task_statuses: lambda do |_connection|
      [%w[Not\ Started Not\ Started], %w[Planned Planned],
       %w[In\ Progress In\ Progress], %w[Completed Completed], %w[On\ Hold In\ Hold]]
    end,

    tax_implications: lambda do |_connection|
      [%w[None None], ['Inbound (Purchase tax)', 'Inbound'],
       ['Outbound (Sales tax)', 'Outbound']]
    end,

    termination_types: lambda do |_connection|
      [%w[Voluntary voluntary], %w[Involuntary involuntary],
       %w[Deceased deceased], %w[Disability disability],
       %w[Retired retired]]
    end,

    termperiods: lambda do |_connection|
      %w[Days Weeks Months Years].map { |val| [val, val] }
    end,

    timesheet_states: lambda do |_connection|
      %w[Draft Submitted].map { |val| [val, val] }
    end,

    tr_types: ->(_connection) { [%w[Debit 1], %w[Credit -1]] },

    transaction_types: lambda do |_connection|
      [%w[Deposit deposit], %w[Withdrawal withdrawal]]
    end,

    transaction_states: lambda do |_connection|
      [%w[Draft Draft], %w[Pending Pending], %w[Closed Closed]]
    end,

    uom_groups: lambda do |_connection|
      %w[Area Count Duration Length Numbers Time Volume Weight].
        map { |val| [val, val] }
    end,

    update_gl_entry_states: lambda do |_connection|
      [%w[Draft Draft], %w[Posted Posted]]
    end,

    usage_quantity_resets: lambda do |_connection|
      ['After each invoice', 'After each renewal'].map { |val| [val, val] }
    end,

    vendors: lambda do |_connection|
      function = {
        '@controlid' => 'testControlId',
        'readByQuery' => {
          'object' => 'VENDOR',
          'fields' => 'NAME, VENDORID',
          'query' => "STATUS = 'T'",
          'pagesize' => '1000'
        }
      }
      response_data = call('get_api_response_data_element', function)

      call('parse_xml_to_hash',
           'xml' => response_data,
           'array_fields' => ['vendor'])&.
        []('vendor')&.
        pluck('NAME', 'VENDORID') || []
    end,

    vsoe_categories: lambda do |_connection|
      ['Product - Specified', 'Software', 'Product - Unspecified',
       'Upgrade - Unspecified', 'Upgrade - Specified', 'Services',
       'Post Contract Support(PCS)'].
        map { |val| [val, val] }
    end,

    vsoedlvrs_statuses: lambda do |_connection|
      %w[Delivered Undelivered].map { |val| [val, val] }
    end,

    vsoerevdef_statuses: lambda do |_connection|
      ['Defer until item is delivered', 'Defer bundle until item is delivered'].
        map { |val| [val, val] }
    end,

    warehouses: lambda do |_connection|
      function = {
        '@controlid' => 'testControlId',
        'readByQuery' => {
          'object' => 'WAREHOUSE',
          'fields' => 'NAME, WAREHOUSEID',
          'query' => "STATUS = 'T'",
          'pagesize' => '1000'
        }
      }
      response_data = call('get_api_response_data_element', function)

      call('parse_xml_to_hash',
           'xml' => response_data,
           'array_fields' => ['warehouse'])&.
        []('warehouse')&.
        pluck('NAME', 'WAREHOUSEID') || []
    end,

    filter_operators: lambda do |_connection|
      [
        %w[Equals equalto],
        %w[Not\ equal\ to notequalto],
        %w[Less\ than lessthan],
        %w[Less\ than\ or\ equal\ to lessthanorequalto],
        %w[Greater\ than greaterthan],
        %w[Greater\ than\ or\ equal\ to greaterthanorequalto],
        %w[Is\ null isnull],
        %w[Is\ not\ null isnotnull],
        %w[Between between],
        %w[In in],
        %w[Not\ in notin],
        %w[Like like],
        %w[Not\ like notlike]
      ]
    end,

    sort_orders: lambda do |_connection|
      [
        %w[Ascending ascending],
        %w[Descending descending]
      ]
    end,

    filter_conditions: lambda do |_connection|
      [
        %w[And and],
        %w[Or or]
      ]
    end,

    orderpricelists: lambda do |_connection|
      function = {
        '@controlid' => 'testControlId',
        'readByQuery' => {
          'object' => 'SOPRICELISTENTRY',
          'fields' => 'PRICELISTID',
          'query' => "STATUS = 'T'",
          'pagesize' => '1000'
        }
      }
      response_data = call('get_api_response_data_element', function)

      call('parse_xml_to_hash',
           'xml' => response_data,
           'array_fields' => ['sopricelistentry'])&.
        []('sopricelistentry')&.uniq&.
        pluck('PRICELISTID', 'PRICELISTID') || []
    end,

    purchasepricelists: lambda do |_connection|
      function = {
        '@controlid' => 'testControlId',
        'readByQuery' => {
          'object' => 'POPRICELISTENTRY',
          'fields' => 'PRICELISTID',
          'query' => "STATUS = 'T'",
          'pagesize' => '1000'
        }
      }
      response_data = call('get_api_response_data_element', function)

      call('parse_xml_to_hash',
           'xml' => response_data,
           'array_fields' => ['popricelistentry'])&.
        []('popricelistentry')&.uniq&.
        pluck('PRICELISTID', 'PRICELISTID') || []
    end
  }
}