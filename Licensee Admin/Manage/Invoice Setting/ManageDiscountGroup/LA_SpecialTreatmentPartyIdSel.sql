/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_SpecialTreatmentPartyIdSel]
AS
/*  
	 Created: 20200529@Mason [#128570]
	 Task : Get all special treatment party Id
	 DB: DB052.bodb_licensee   

	 Revisions:  
		- 20200529@Mason: INH Treatment market [#128570]
	 Params:

	 Explannation: EXEC LA_SpecialTreatmentPartyIdSel 
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @CurrentTime DATETIME = GETDATE()

	-- Get list of special treatment parties
	SELECT ps.PartyId
	FROM dbo.LA_PartySpecialTreatment ps WITH (NOLOCK)
	WHERE @CurrentTime BETWEEN ps.FromDate AND ps.ToDate
END
GO