/*<info serverAlias="DBCUST-bodb_licensee"></info>*/
/*
	Created: 20250429@Danny
	DB: DBCUST.bodb_licensee
	Description: Add new invoice template [RedmineID: #222972]
*/

USE bodb_licensee
GO

-- Add New Invoice Template
INSERT INTO dbo.LA_InvoiceTemplate (InvTemplateName, TemplatePath)
SELECT t.InvTemplateName, '' AS TemplatePath
FROM (
		VALUES ('Internal-Settlement')
		      ,('Credit-Internal-Settlement')
		      ,('Debit-Internal-Settlement')

) t(InvTemplateName)
	LEFT JOIN dbo.LA_InvoiceTemplate it WITH (NOLOCK) ON it.InvTemplateName = t.InvTemplateName
WHERE it.InvTemplateName IS NULL