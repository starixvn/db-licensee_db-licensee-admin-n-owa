/*<info serverAlias="DBLIC-bodb_licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE dbo.LA_ProductListSelAll
	@IsProductExclude BIT = 0
	,@LicenseeId 	  INT = 0
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
		- 20250526@Eddie: Get products follow Lap Licensees [RedmineID: #211102]
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
		LEFT JOIN dbo.LicenseeProduct3rd lp WITH (NOLOCK) ON lp.ProductId = p.ProductId
		LEFT JOIN dbo.Product3rd pr WITH(NOLOCK) ON p.ProductId = pr.Productid
	WHERE p.ProductId = p.GroupProductId 
		AND p.ProductCode NOT IN ('VS4','SAC')
		AND (@IsProductExclude = 0 OR NOT (ISNULL(pr.OfferSite, '') = 1 OR pr.EndOfSupportDate IS NOT NULL OR p.ProductName = 'Saba Promotion'))
		AND ( lp.LicenseeId = @LicenseeId OR ISNULL(@LicenseeId, 0) = 0 )
	GROUP BY p.ProductID, p.ProductName, p.ProductCode
	ORDER BY p.ProductID
END
GO
