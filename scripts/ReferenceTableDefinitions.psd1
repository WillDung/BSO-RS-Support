@{
    os_sr_ta = @{
        DisplayName = 'TA Directory'
        DisplayCollectionName = 'TA Directories'
        PluralApproved = $true
        OwnershipType = 'OrganizationOwned'
        PrimaryName = @{
            SchemaName = 'os_sr_ta_nm'; DisplayName = 'TA Name'
            AttributeType = 'String'; FormatName = 'Text'; MaxLength = 200
            RequiredLevel = 'ApplicationRequired'; IsPrimaryName = $true
        }
        Columns = @(
            @{
                SchemaName = 'os_sr_ta_eml'; DisplayName = 'TA Email'
                AttributeType = 'String'; FormatName = 'Email'; MaxLength = 254
                RequiredLevel = 'ApplicationRequired'; IsPrimaryName = $false
            }
        )
    }
    os_sr_pos = @{
        DisplayName = 'Position'
        DisplayCollectionName = 'Positions'
        PluralApproved = $true
        OwnershipType = 'OrganizationOwned'
        PrimaryName = @{
            SchemaName = 'os_sr_pos_ttl'; DisplayName = 'Position Title'
            AttributeType = 'String'; FormatName = 'Text'; MaxLength = 200
            RequiredLevel = 'ApplicationRequired'; IsPrimaryName = $true
        }
        Columns = @()
    }
    os_sr_csrc = @{
        DisplayName = 'Candidate Source'
        DisplayCollectionName = 'Candidate Sources'
        PluralApproved = $true
        OwnershipType = 'OrganizationOwned'
        PrimaryName = @{
            SchemaName = 'os_sr_csrc_nm'; DisplayName = 'Source Name'
            AttributeType = 'String'; FormatName = 'Text'; MaxLength = 100
            RequiredLevel = 'ApplicationRequired'; IsPrimaryName = $true
        }
        Columns = @()
    }
    os_sr_loc = @{
        DisplayName = 'Location'
        DisplayCollectionName = 'Locations'
        PluralApproved = $true
        OwnershipType = 'OrganizationOwned'
        PrimaryName = @{
            SchemaName = 'os_sr_loc_nm'; DisplayName = 'Location Name'
            AttributeType = 'String'; FormatName = 'Text'; MaxLength = 150
            RequiredLevel = 'ApplicationRequired'; IsPrimaryName = $true
        }
        Columns = @(
            @{
                SchemaName = 'os_sr_loc_rmeml'; DisplayName = 'Room/Resource Email'
                AttributeType = 'String'; FormatName = 'Email'; MaxLength = 254
                RequiredLevel = 'None'; IsPrimaryName = $false
            }
            @{
                SchemaName = 'os_sr_loc_det'; DisplayName = 'Location Details'
                AttributeType = 'Memo'; FormatName = 'Text'; MaxLength = 1000
                RequiredLevel = 'None'; IsPrimaryName = $false
            }
        )
    }
}