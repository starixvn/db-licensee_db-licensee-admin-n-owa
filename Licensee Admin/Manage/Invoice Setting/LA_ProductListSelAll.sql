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
		- 20210812@Percy: Exclude BitCoin from Product drop-down list [RedmineID: #159691]
*/
BEGIN
	SET NOCOUNT ON

	SELECT p.ProductId, p.ProductName, p.ProductPrefix AS ProductCode
	FROM dbo.LA_f_Products3rd('') p
		LEFT JOIN dbo.LA_f_GroupProduct() g ON p.ProductId = g.ProductId AND g.ProductId <> g.GroupProductId
	WHERE g.ProductId IS NULL
END
GO