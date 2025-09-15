/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20250915@Danny
	DB: DBCUST.bodb_Licensee
	Task: Configure Balance Carry Forward [#225392]
	Description: Create new table
*/
USE bodb_Licensee
GO


CREATE TABLE [dbo].[SH_SabaPlay_BalanceCarryForwardSetting](
	[PartyID] [int] NOT NULL,
	[FromDate] [date] NOT NULL,
	[ToDate] [date] NOT NULL,
	[IsBalanceCarryForward] [BIT] NOT NULL
 CONSTRAINT [PK_SH_SabaPlay_BalanceCarryForwardSetting] PRIMARY KEY CLUSTERED 
(
	[PartyID] ASC,
	[FromDate] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [OWA_DATA]
) ON [OWA_DATA]
GO


-- Initial data


INSERT INTO SH_SabaPlay_BalanceCarryForwardSetting (PartyID, FromDate, ToDate, IsBalanceCarryForward)

SELECT op.PartyID , opd.LaunchDate, '2025-01-01', CASE WHEN op.PartyName IN ('UnicornSP','GLO365SP') THEN 0 ELSE 1 END
FROM OAS_Party op WITH(NOLOCK) 
INNER JOIN OAS_PartyDetail opd WITH(NOLOCK) ON op.PartyID = opd.PartyID
WHERE op.PlatformId = 2 AND NOT EXISTS (
	SELECT TOP 1 1 FROM SH_SabaPlay_BalanceCarryForwardSetting os WITH(NOLOCK) WHERE os.PartyID = op.PartyID
) AND opd.LaunchDate IS NOT NULL




