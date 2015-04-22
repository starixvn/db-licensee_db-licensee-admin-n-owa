USE bodb_licensee
GO
CREATE PROCEDURE dbo.LA_DiscountGroupListSel @DiscountType TINYINT
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
	WHERE DiscountGroupType = @DiscountType
END