USE bodb_licensee
GO
ALTER PROCEDURE dbo.LA_DiscountGroupListSel @DiscountGroupType TINYINT
AS
/*  
	 Created: 20150422@Patrick
	 Task : Discount group select
	 DB: DB052.bodb_Licensee
	 Revisions:     
		
	 Params:
*/
BEGIN
	SET NOCOUNT ON
	SELECT DiscountGroupId, DiscountGroupName
	FROM dbo.LA_DiscountGroupHeader WITH(NOLOCK)
	WHERE DiscountGroupType = @DiscountGroupType
END
GO
GRANT VIEW DEFINITION ON dbo.LA_DiscountGroupListSel TO vnteam
GRANT EXECUTE ON dbo.LA_DiscountGroupListSel TO bodbAdminNet
GO