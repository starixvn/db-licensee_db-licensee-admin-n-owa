/*<info serverAlias="DBLIC-bodb_licensee" selecters="bodbAdminNet" isFunction="1" isNested="1"></info>*/
USE bodb_licensee
GO

ALTER FUNCTION [dbo].[LA_f_GroupProduct] ()
RETURNS TABLE
AS

/*
	Created: 20210812@Percy
	DB: DBLIC-bodbLicensee
	Task: Core function - Group Product

	Revisions:
		- 20210812@Percy: Initialize function [RedmineID: #159691]
*/

RETURN
	-- SB
	SELECT CONVERT(INT, 0) AS ProductId, CONVERT(INT, 0) AS GroupProductId
	UNION ALL SELECT 69, 0 -- Bitcoin
GO