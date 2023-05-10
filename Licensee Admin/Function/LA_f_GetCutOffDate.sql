/*<info serverAlias="DBCUST-bodb_licensee,DBLIC-bodb_licensee" selecters="bodbAdminNet,bodbLicenseeNet" isFunction="1" isNested="1"></info>*/
USE bodb_licensee
GO

CREATE FUNCTION [dbo].[LA_f_GetCutOffDate]()
RETURNS TABLE
AS

/*  
	 Created: 20230510@Danny
	 DB: DBCUST-bodb_licensee,DBLIC-bodb_licensee
	 Task: LA cutoff Date
	 
	 Revisions:
		- 20230510@Danny: Initialize function [RedmineID: #186543]
*/

RETURN
	SELECT CutoffDate, TypeName
	FROM (
		VALUES ('2023-05-01', 'ExchangeTerms')
	) AS t (CutoffDate, TypeName)

GO