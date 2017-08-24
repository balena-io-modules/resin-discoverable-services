{
    'targets': [{
        'target_name': 'dns_sd_bindings',
        'sources': [
            'lib/backends/dns-sd-bindings/dns_sd.cpp',
            'lib/backends/dns-sd-bindings/dns_service_browse.cpp',
            'lib/backends/dns-sd-bindings/dns_service_enumerate_domains.cpp',
            'lib/backends/dns-sd-bindings/dns_service_get_addr_info.cpp',
            'lib/backends/dns-sd-bindings/dns_service_process_result.cpp',
            'lib/backends/dns-sd-bindings/dns_service_ref.cpp',
            'lib/backends/dns-sd-bindings/dns_service_ref_deallocate.cpp',
            'lib/backends/dns-sd-bindings/dns_service_ref_sock_fd.cpp',
            'lib/backends/dns-sd-bindings/dns_service_register.cpp',
            'lib/backends/dns-sd-bindings/dns_service_resolve.cpp',
            'lib/backends/dns-sd-bindings/dns_service_update_record.cpp',
            'lib/backends/dns-sd-bindings/mdns_utils.cpp',
            'lib/backends/dns-sd-bindings/network_interface.cpp',
            'lib/backends/dns-sd-bindings/socket_watcher.cpp',
            'lib/backends/dns-sd-bindings/txt_record_ref.cpp',
            'lib/backends/dns-sd-bindings/txt_record_create.cpp',
            'lib/backends/dns-sd-bindings/txt_record_deallocate.cpp',
            'lib/backends/dns-sd-bindings/txt_record_set_value.cpp',
            'lib/backends/dns-sd-bindings/txt_record_get_length.cpp',
            'lib/backends/dns-sd-bindings/txt_record_buffer_to_object.cpp'
        ],
        'conditions': [
            ['OS!="mac" and OS!="win"', {
				'libraries': [
					'-ldns_sd'
				]
			}],
            ['OS=="mac"', {
                'defines': [
                    'HAVE_DNSSERVICEGETADDRINFO'
                ]
            }],
            ['OS=="freebsd"', {
				'include_dirs': [
					'/usr/local/include'
				],
				'libraries': [
					'-L/usr/local/lib'
				]
			}],
            ['OS=="win"', {
                'variables': {
					'BONJOUR_SDK_DIR': '$(BONJOUR_SDK_HOME)', # Preventing path resolution problems by saving the env var in variable first
					'PLATFORM': '$(Platform)' # Set  the platform
                },
                'include_dirs': [
                    '<(BONJOUR_SDK_DIR)/Include'
                ],
                'defines': [
                    'HAVE_DNSSERVICEGETADDRINFO'
                ],
                'libraries': [
                    '-l<(BONJOUR_SDK_DIR)/Lib/<(PLATFORM)/dnssd.lib',
                    '-lws2_32.lib',
                    '-liphlpapi.lib'
                ]
            }]
        ],
        "include_dirs": [
            "<!(node -e \"require('nan')\")"
        ],
		# The following breaks the debug build, so just ignore the warning for now.
		#, 'msbuild_settings': {
		#    'ClCompile': { 'ExceptionHandling': 'Sync' }
		#  , 'Link'     : { 'IgnoreSpecificDefaultLibraries': [ 'LIBCMT' ] }
		#  }
        'msbuild_settings': {
            'ClCompile': {
                'ExceptionHandling': 'Sync'
            },
            'Link': {
                'IgnoreSpecificDefaultLibraries': [
                    'LIBCMT'
                ]
            }
        },
        'configurations': {
            'Release': {
                'xcode_settings': {
                    'GCC_OPTIMIZATION_LEVEL': 3
                },
                'cflags': [
                    '-O3'
                ],
                'ldflags': [
                    '-O3'
                ]
            },
            'Debug': {
                'xcode_settings': {
                    'GCC_OPTIMIZATION_LEVEL': 0
                },
                'cflags': ['-g',
                    '-O0',
                ],
                'ldflags': [
                    '-g',
                    '-O0'
                ]
            },
            'Coverage': {
                'xcode_settings': {
                    'GCC_OPTIMIZATION_LEVEL': 0,
                    'OTHER_LDFLAGS': [
                        '--coverage'
                    ],
                    'OTHER_CFLAGS': [
                        '--coverage'
                    ]
                },
                'cflags': [
                    '-O0',
                    '--coverage'
                ],
                'ldflags': [
                    '--coverage'
                ]
            }
        }
    }]
}
