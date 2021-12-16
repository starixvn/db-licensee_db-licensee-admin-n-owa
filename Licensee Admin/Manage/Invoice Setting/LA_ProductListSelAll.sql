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
		- 20211026@Danny: Treat SLT as a part of SB based on cutoff date [RedmineID: #163181]
*/
BEGIN
	SET NOCOUNT ON

	SELECT p.ProductID, p.ProductName, p.ProductCode  
	FROM dbo.LA_f_GroupProduct('',NULL,NULL) p
	WHERE p.ProductId = p.GroupProductId

END
GO