/*<info serverAlias="DBLIC-bodb_licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE dbo.LA_ProductListSelAll
	@IsProductExclude BIT = 0
AS
/*  
	Created: 20150422@Patrick
	Task : Get all products
	DB: DBLIC.bodb_Licensee
	
	Revisions:     
		- 20190128@Bruce: include product code [redmine: #108311]
		- 20210812@Percy: Exclude BitCoin from Product drop-down list [RedmineID: #159691]
		- 20211026@Danny: Treat SLT as a part of SB based on cutoff date [RedmineID: #163181]
		- 20221018@Malcolm: Exclude products which support Credit site only,  obsolete products, Saba Promotio [RedmineId : #171705]
		- 20231106@Malcolm: Hard code to show Casino promotion product [RedmineId : #194808]
		- 20240312@Danny: Not show VS4 on dropdown [RemineID: #199478]
		- 20240419@Danny: Remove Saba Coin [RedmineID: #203331]
*/
BEGIN
	SET NOCOUNT ON

	SELECT p.ProductID, p.ProductName, p.ProductCode  
	FROM 
		(	
			SELECT ProductID, ProductName, ProductCode ,GroupProductId
			FROM dbo.LA_f_GroupProduct('',NULL,NULL) 
			UNION ALL
			SELECT -37, 'Non-Sportsbook Promotion', 'SPR(CS)', -37
		)p
		LEFT JOIN dbo.Product3rd pr WITH(NOLOCK) ON p.ProductId = pr.Productid
	WHERE p.ProductId = p.GroupProductId 
		AND p.ProductCode NOT IN ('VS4','SAC')
		AND (@IsProductExclude = 0 OR NOT (ISNULL(pr.OfferSite, '') = 1 OR pr.EndOfSupportDate IS NOT NULL OR p.ProductName = 'Saba Promotion'))

END
GO
