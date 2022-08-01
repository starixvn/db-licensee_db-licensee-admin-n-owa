/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE dbo.LA_VendorPaymentProductListSel
	@UserID	INT = 0 
	,@FunctionKey	NVARCHAR(100)	= ''
AS
/*  
	Created: 20220324@Danny
	Task : Get all vendor products
	DB: DBCUST.bodb_Licensee
	
	Revisions:     
		- 20220324@Danny: Create SP [RedmineID: #168387]

*/
BEGIN
	SET NOCOUNT ON

	IF @UserID = 0 
	BEGIN
		SELECT	p.ProductID AS ProductID, p.ProductName AS ProductName
		FROM	dbo.Product3rd p WITH(NOLOCK)
		WHERE	p.Enabled = 1 

		UNION ALL
		SELECT 1000 AS ProductID, 'Bet Builder' AS ProductName

		UNION ALL
		SELECT 1001 AS ProductID, 'Muay Thai' AS ProductName

		ORDER BY  ProductID
	END
	ELSE
	BEGIN
		DECLARE @Parent_FunctionID INT
		SELECT @Parent_FunctionID = FunctionID
		FROM dbo.LA_Function WITH(NOLOCK)
		WHERE FunctionKey = @FunctionKey

		;WITH func_list AS
		(
			SELECT FunctionID, FunctionKey
			FROM dbo.LA_Function WITH(NOLOCK)
			WHERE ParentID = @Parent_FunctionID
		),
		permission_list AS
		(
			SELECT REPLACE(f.FunctionKey,'VendorPaymentInDetails_','') ProductPrefix
			FROM dbo.LA_UserFunction u WITH(NOLOCK)
			INNER JOIN func_list f ON u.FunctionID = f.FunctionID
			WHERE  UserID =  @UserID AND u.StatusID = 1
		), result AS
		(
		SELECT		CASE WHEN t.ProductPrefix = 'BetBuilder' THEN 1000
						 WHEN t.ProductPrefix = 'MuayThai'	 THEN 1001
						 ELSE p.Productid END AS ProductID,
					CASE WHEN t.ProductPrefix = 'BetBuilder' THEN 'Bet Builder'
						 WHEN t.ProductPrefix = 'MuayThai'	 THEN 'Muay Thai'
						 ELSE p.ProductName END AS ProductName,
					t.ProductPrefix AS ProductCode
		FROM		permission_list t
		LEFT JOIN	dbo.Product3rd p WITH(NOLOCK) ON t.ProductPrefix = p.ProductPrefix
		)
		SELECT r.ProductID, r.ProductName, r.ProductCode
		FROM result r
		INNER JOIN LA_VendorPaymentSetting lv WITH(NOLOCK) ON r.ProductID = lv.ProductId
		WHERE lv.IsActive = 1
		ORDER BY r.ProductID
	END 

END
GO

