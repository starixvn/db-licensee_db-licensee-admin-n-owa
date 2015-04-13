USE [bodb_licensee]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_BillerDel] 
	@BillerID	INT	
	, @ErrCode	INT				= 0		OUTPUT
	, @ErrMsg	NVARCHAR(1000)	= ''	OUTPUT
AS
/*  
	 Created: 20150408@Florent
	 Task : Delete Biller Information
	 DB: DB052.bodb_Licensee  
   
	 Revisions:     
*/
SET NOCOUNT ON

BEGIN
	--check exist
	IF ISNULL(@BillerID, '') = ''
		RETURN
	-- only can delete which Biller dont issue any invoice on system
	DECLARE @CanDel BIT = 0
	SELECT @CanDel = 1 FROM dbo.OAS_Party p WITH (NOLOCK)
			INNER JOIN dbo.LA_BillerInfo b WITH (NOLOCK) ON p.PartyID = b.PartyID			
			INNER JOIN dbo.LA_InvoiceSetting i WITH (NOLOCK) ON i.FromPartyId = p.PartyID
			-- check exists biller in table Incoive
	WHERE p.PartyType = 4 -- biller
			AND p.PartyID = @BillerId

	IF NOT EXISTS (SELECT 1 FROM dbo.OAS_Party p WITH (NOLOCK)
									INNER JOIN dbo.LA_BillerInfo b WITH (NOLOCK) ON p.PartyID = b.PartyID			
									INNER JOIN dbo.LA_InvoiceSetting i WITH (NOLOCK) ON i.FromPartyId = p.PartyID
							WHERE p.PartyType = 4 -- biller
									AND p.PartyID = @BillerId)
		BEGIN
			
			DELETE dbo.OAS_Party WITH (ROWLOCK, UPDLOCK)
			WHERE PartyType = 4 AND PartyID = @BillerId

			DELETE dbo.LA_BillerInfo WITH (ROWLOCK, UPDLOCK)
			WHERE PartyId = @BillerId
						
			BEGIN
			SELECT @ErrCode = 101
				,@ErrMsg = 'The Biller is deleted successfully'
			RETURN
		END
		END
	ELSE	
		BEGIN
			SELECT @ErrCode = 101
			,@ErrMsg = 'The Biller cannot be deleted because it''s already responsible for billing!'
			RETURN
		END	
	--Write Log	
END
GO
GRANT VIEW DEFINITION ON [dbo].[LA_BillerDel] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_BillerDel] TO bodbAdminNet 