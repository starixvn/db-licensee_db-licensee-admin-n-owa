/*<info serverAlias="DBCUST-bodb_Licensee"></info>*/
USE bodb_Licensee
GO

CREATE VIEW [dbo].[vw_SabaPlay_Products]
/*
    Created: 20250326@Eddie
    DB: DBCUST.bodb_Licensee
	Description: Create view to get all SabaPlay Products [RedmineID: #217740]
*/
AS

	SELECT ProductID, ProductName
	FROM DBLIC.bodb_licenseeReport.dbo.SabaPlay_Products WITH (NOLOCK)

GO