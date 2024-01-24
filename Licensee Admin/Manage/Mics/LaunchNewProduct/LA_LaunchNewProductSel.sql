/*<info serverAlias="DBLIC-bodb_licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
CREATE PROCEDURE [dbo].[LA_LaunchNewProductSel]
	@ProductCode	 VARCHAR(10)
	,@PayerNameList NVARCHAR(MAX) 
AS
/*
	Created: 20220919@Malcolm
	Task : Launch new licensee
	DB: DBLIC.bodb_Licensee

	Revisions:
		- 20220919@Malcolm: Launch new Product [RedmineID: #175860]
		
	Param's Explannation: 

*/
BEGIN
	SET NOCOUNT ON
	
	DECLARE @ProductId INT
	
	SELECT @PayerNameList = ISNULL(@PayerNameList, '')

	SELECT @ProductId = p.ProductID
	FROM dbo.LA_f_GroupProduct('',NULL,NULL) p
	WHERE p.ProductId = p.GroupProductId AND GroupProductCode= @ProductCode

	SELECT op.PartyID, op.PartyName, pd.InvoiceLanguage
	FROM dbo.OAS_Party op WITH(NOLOCK)
		INNER JOIN dbo.OAS_PartyDetail pd WITH(NOLOCK) ON pd.PartyID = op.PartyID
		INNER JOIN dbo.LicenseeProduct3rd lp WITH(NOLOCK) ON lp.LicenseeID = op.OldRefID AND lp.ProductID = @ProductId AND ISNULL(pd.IsDeposit, 0) = 1
	WHERE lp.ProductID = @ProductId AND op.PartyType = 1 AND pd.StatusId = 1
		AND op.PartyName IN (SELECT LTRIM(RTRIM(value)) FROM STRING_SPLIT(@PayerNameList, ','))
		AND pd.SuspendedDate IS NULL AND pd.TerminatedDate IS NULL
	ORDER BY op.PartyName ASC

END
GO