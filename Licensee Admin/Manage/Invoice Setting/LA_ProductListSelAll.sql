/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE dbo.LA_ProductListSelAll
AS
/*  
	Created: 20150422@Patrick
	Task : Get all products
	DB: DBLIC.bodb_Licensee
	
	Revisions:     
		- 20190128@Bruce: include product code [redmine: #108311]
*/
BEGIN
	SET NOCOUNT ON

	SELECT ProductId, ProductName, ProductPrefix AS ProductCode
	FROM dbo.LA_f_Products3rd('')
END
GO